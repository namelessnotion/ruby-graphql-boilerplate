# frozen_string_literal: true
# typed: false

require 'opentelemetry/sdk'

# Collects the spans an example produces, so span emission can be asserted
# without a collector running.
#
# `.env.test` sets OTEL_SDK_DISABLED=true, which leaves the global tracer
# provider as the API's no-op — that is the path the rest of the suite
# exercises. An example that asserts on span contents installs a real SDK
# provider for its own duration and puts the no-op back afterwards.
RSpec.shared_context 'with recorded spans' do
  let(:span_exporter) { OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new }

  # Not a `let`: InMemorySpanExporter#finished_spans returns a copy, so
  # memoizing it would freeze the list at whatever the first call saw.
  def recorded_spans
    span_exporter.finished_spans
  end

  def recorded_span_named(name)
    recorded_spans.find { |span| span.name == name }
  end

  around do |example|
    previous_propagation = OpenTelemetry.propagation

    provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    # Simple rather than batch: spans land in the exporter synchronously, so
    # an example can assert on them without waiting for an export interval.
    provider.add_span_processor(
      OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(span_exporter)
    )

    OpenTelemetry.tracer_provider = provider
    # Mirrors the propagator OpenTelemetry::SDK.configure installs in
    # production; without it an inbound `traceparent` cannot be extracted.
    OpenTelemetry.propagation = OpenTelemetry::Trace::Propagation::TraceContext.text_map_propagator

    example.run

    # Not the provider that was there before: OpenTelemetry.tracer_provider=
    # hands the API's ProxyTracerProvider a delegate the first time it is
    # called and then refuses to reset it, so putting that proxy back would
    # leave the following examples still delegating to this example's dead SDK
    # provider. The API's own base TracerProvider is the no-op this is
    # restoring to anyway.
    OpenTelemetry.tracer_provider = OpenTelemetry::Trace::TracerProvider.new
    OpenTelemetry.propagation = previous_propagation
  end
end
