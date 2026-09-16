# frozen_string_literal: true
# typed: strict

require 'fileutils'
require 'json'
require 'logger'
require 'time'

# Only the API here, never the SDK: this is the half that has to work with
# nothing running. Requiring the SDK, the OTLP exporter and the protobuf
# runtime is deferred to `configure!`, so a process with OTEL_SDK_DISABLED set
# — every test run, by default — never pays for them.
require 'opentelemetry-api'
require 'opentelemetry-semantic_conventions'

# Tracing and structured logging for the Ruby API.
#
# Two tiers, because the OpenTelemetry signals are not equally mature. Traces
# come from the stable SDK (1.x). Logs are plain JSON on stdout rather than the
# pre-1.0 logs SDK, and metrics are left for the collector to derive from spans
# rather than pulling in the pre-1.0 metrics SDK. Correlation between the two
# tiers needs only the stable trace API: every log line carries the trace_id
# and span_id of the span in scope when it was written.
#
# Tier 1 (structured stdout logs) is always on. Tier 2 (OTLP export) turns on
# only when `configure!` runs without OTEL_SDK_DISABLED, which leaves the
# global tracer provider as the API's no-op the rest of the time — spans still
# open and close, they just record nothing and cost nothing.
module Observability
  extend T::Sig

  # The values OpenTelemetry accepts as span attributes.
  AttributeValue = T.type_alias { T.any(String, Symbol, Integer, Float, T::Boolean, NilClass) }

  # Named once and used for both the OTel resource and the `service.name` on
  # every log line, so a trace and its logs always agree on who emitted them.
  SERVICE_NAME = T.let(ENV.fetch('OTEL_SERVICE_NAME', 'stack-api'), String)
  SERVICE_VERSION = T.let(ENV.fetch('APP_VERSION', '0.0.0'), String)

  # Identifies this app's own hand-written spans, as distinct from the spans
  # the instrumentation gems emit for pg, redis, graphql and resque.
  INSTRUMENTATION_NAME = 'stack'

  class << self
    extend T::Sig

    # True when OTEL_SDK_DISABLED is set to "true" — the switch between the two
    # tiers. `.env.test` sets it, so the suite exercises the no-op path and
    # never depends on a collector being up.
    sig { returns(T::Boolean) }
    def disabled?
      ENV.fetch('OTEL_SDK_DISABLED', 'false').strip.downcase == 'true'
    end

    # Installs the trace SDK and the instrumentation patches. Call this once,
    # during boot, before anything opens a database or Redis connection: the
    # instrumentation gems patch client classes, and a connection created
    # before the patch lands is never traced.
    sig { void }
    def configure!
      return if disabled?

      require_sdk!

      # The SDK's own diagnostics — instrumentation that installed, exporters
      # that could not reach the collector — otherwise go to stdout as plain
      # text, interleaved with the JSON lines below. One stream, one format.
      OpenTelemetry.logger = Log.logger

      OpenTelemetry::SDK.configure do |config|
        config.service_name = SERVICE_NAME
        config.service_version = SERVICE_VERSION
        config.resource = deployment_resource
        install_instrumentation(config)
      end
    end

    # Opens a span around `block`, and returns whatever the block returned.
    # The single entry point the rest of the app uses; nothing outside this
    # file should need to reach for OpenTelemetry directly.
    #
    # An exception raised inside the block is recorded on the span, marks it
    # failed, and is re-raised untouched.
    sig do
      type_parameters(:Result)
        .params(
          name: String,
          kind: T.nilable(Symbol),
          attributes: AttributeValue,
          '&': T.proc.params(span: OpenTelemetry::Trace::Span).returns(T.type_parameter(:Result))
        )
        .returns(T.type_parameter(:Result))
    end
    def in_span(name, kind: nil, **attributes, &)
      tracer.in_span(name, kind: kind, attributes: attributes.transform_keys(&:to_s), &)
    end

    # Continues a trace that started upstream — a browser, or another service —
    # by reading the W3C `traceparent` header out of the Rack env. Spans opened
    # inside the block hang off that remote parent instead of starting a new
    # trace. With no such header, or with the SDK disabled, the block simply
    # runs in the current context.
    sig do
      type_parameters(:Result)
        .params(
          env: T::Hash[String, T.untyped],
          '&': T.proc.returns(T.type_parameter(:Result))
        )
        .returns(T.type_parameter(:Result))
    end
    def continue_trace(env, &)
      context = OpenTelemetry.propagation.extract(
        env,
        getter: OpenTelemetry::Common::Propagation.rack_env_getter
      )

      OpenTelemetry::Context.with_current(context, &)
    end

    # Attaches `error` to the span in scope as an event, leaving the span's
    # status alone.
    #
    # The callers are the GraphQL `rescue_from` handlers, where the exceptions
    # are client errors — a note that does not exist, a validation that failed,
    # a transition that was not allowed. Marking those spans failed would put
    # them in the error rate the collector derives from spans, where they would
    # read as the API breaking rather than as a client asking for the wrong
    # thing. The event keeps the detail on the trace either way.
    sig { params(error: Exception).void }
    def record_exception(error)
      OpenTelemetry::Trace.current_span.record_exception(error)
    end

    private

    # Pulled in here rather than at the top of the file so that a disabled
    # process never loads the SDK, the OTLP exporter or protobuf at all.
    sig { void }
    def require_sdk!
      require 'opentelemetry/sdk'
      require 'opentelemetry-exporter-otlp'
      require 'opentelemetry-instrumentation-graphql'
      require 'opentelemetry-instrumentation-pg'
      require 'opentelemetry-instrumentation-redis'
      require 'opentelemetry-instrumentation-resque'
    end

    # Which deployment these spans came from — the one resource attribute the
    # SDK cannot work out on its own.
    sig { returns(T.untyped) }
    def deployment_resource
      OpenTelemetry::SDK::Resources::Resource.create(
        OpenTelemetry::SemanticConventions::Resource::DEPLOYMENT_ENVIRONMENT => APP_ENV
      )
    end

    sig { params(config: T.untyped).void }
    def install_instrumentation(config)
      config.use 'OpenTelemetry::Instrumentation::GraphQL'
      config.use 'OpenTelemetry::Instrumentation::PG'
      config.use 'OpenTelemetry::Instrumentation::Redis'
      # Resque ends a job's forked child with `exit!`, which skips the at_exit
      # hook that would otherwise drain the batch processor. Stated explicitly
      # rather than left to the default, because the failure it prevents —
      # every worker span silently lost — looks like nothing at all.
      # :ask_the_job flushes only when the worker actually forks.
      config.use 'OpenTelemetry::Instrumentation::Resque', { force_flush: :ask_the_job }
    end

    # Deliberately not memoized. The tracer has to follow the global provider,
    # which the SDK swaps in at `configure!` and which specs swap for an
    # in-memory one; a cached tracer would keep writing to whichever provider
    # happened to be installed first.
    sig { returns(OpenTelemetry::Trace::Tracer) }
    def tracer
      OpenTelemetry.tracer_provider.tracer(INSTRUMENTATION_NAME, SERVICE_VERSION)
    end
  end

  # Structured logging on stdout — tier 1, always on.
  #
  # One JSON object per line, which is what every log pipeline can read
  # without a parser of its own, and what makes a log line joinable to the
  # trace it belongs to.
  module Log
    extend T::Sig

    # Extra fields callers attach to a line, alongside the message. Taken as
    # one hash rather than as keyword arguments because the keys are dotted
    # semantic-convention names, which are constants at most call sites and so
    # cannot be written as keywords.
    FieldValue = T.type_alias { T.any(String, Symbol, Integer, Float, T::Boolean, NilClass) }
    Fields = T.type_alias { T::Hash[String, FieldValue] }

    # Renders a log entry as a single line of JSON, stamped with the trace and
    # span it was written inside.
    class Formatter
      extend T::Sig

      sig do
        params(
          severity: String,
          time: Time,
          _progname: T.untyped,
          message: T.untyped
        ).returns(String)
      end
      def call(severity, time, _progname, message)
        entry = {
          'timestamp' => time.utc.iso8601(3),
          'level' => severity,
          'service.name' => SERVICE_NAME
        }

        "#{JSON.generate(entry.merge(fields_of(message), correlation))}\n"
      end

      private

      # A Hash message carries its own fields; anything else is the message.
      sig { params(message: T.untyped).returns(T::Hash[String, T.untyped]) }
      def fields_of(message)
        return message.transform_keys(&:to_s) if message.is_a?(Hash)

        { 'message' => message.to_s }
      end

      # Absent outside a span, rather than present and invalid — a line with no
      # trace to join to should not carry a string of zeroes that looks like one.
      sig { returns(T::Hash[String, String]) }
      def correlation
        context = OpenTelemetry::Trace.current_span.context
        return {} unless context.valid?

        { 'trace_id' => context.hex_trace_id, 'span_id' => context.hex_span_id }
      end
    end

    class << self
      extend T::Sig

      @logger = T.let(nil, T.nilable(::Logger))

      sig { returns(::Logger) }
      def logger
        @logger ||= T.let(build_logger, T.nilable(::Logger))
      end

      sig { params(message: String, fields: Fields).void }
      def debug(message, fields = {}) = write(:debug, message, fields)

      sig { params(message: String, fields: Fields).void }
      def info(message, fields = {}) = write(:info, message, fields)

      sig { params(message: String, fields: Fields).void }
      def warn(message, fields = {}) = write(:warn, message, fields)

      sig { params(message: String, fields: Fields).void }
      def error(message, fields = {}) = write(:error, message, fields)

      private

      sig { params(level: Symbol, message: String, fields: Fields).void }
      def write(level, message, fields)
        logger.public_send(level, { 'message' => message }.merge(fields))
      end

      sig { returns(::Logger) }
      def build_logger
        device = log_device

        # Unbuffered: under Falcon and under `docker compose logs`, a buffered
        # stdout holds lines back until the buffer fills, which is exactly when
        # they are least useful.
        device.sync = true

        ::Logger.new(
          device,
          level: ENV.fetch('LOG_LEVEL', 'info'),
          formatter: Formatter.new
        )
      end

      # $stdout unless LOG_FILE is set, so nothing changes for a process that
      # never sets it. The app runs on the host via `bin/server`, not in a
      # container, so there is no container stdout for the collector's
      # `filelog` receiver to scrape — a file is the seam (see
      # docker/otel/otelcol-config.yaml).
      sig { returns(IO) }
      def log_device
        path = ENV.fetch('LOG_FILE', nil)
        return $stdout if path.nil? || path.empty?

        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, 'a')
      end
    end
  end
end
