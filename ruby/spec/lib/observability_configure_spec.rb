# frozen_string_literal: true
# typed: false

require 'open3'

RSpec.describe Observability, :aggregate_failures do
  describe '.configure!' do
    # Installing the SDK is a process-wide, one-way change, and the suite
    # itself runs with OTEL_SDK_DISABLED=true — so the enabled half of the two
    # tiers is exercised in a subprocess that boots the app for real.
    #
    # OTEL_TRACES_EXPORTER=none keeps that subprocess from reaching for a
    # collector that is not running; what it would have exported is captured in
    # memory instead, by a processor added once configure! has done its work.
    let(:script) do
      <<~RUBY
        require './lib/environment'
        require 'json'

        exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
        OpenTelemetry.tracer_provider.add_span_processor(
          OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
        )

        # `begin` so a probe can set something up before its closing hash.
        puts JSON.generate(begin
          #{probe}
        end)
      RUBY
    end

    let(:booted) do
      stdout, status = Open3.capture2(
        { 'APP_ENV' => 'test', 'OTEL_SDK_DISABLED' => 'false', 'OTEL_TRACES_EXPORTER' => 'none' },
        'bundle', 'exec', 'ruby', '-e', script
      )
      raise "booting with the SDK enabled failed:\n#{stdout}" unless status.success?

      JSON.parse(stdout.lines.last)
    end

    context 'with the SDK enabled' do
      let(:probe) do
        <<~PROBE
          {
            'provider' => OpenTelemetry.tracer_provider.class.name,
            'recording' => Observability.in_span('probe') { |span| span.recording? }
          }.merge(OpenTelemetry.tracer_provider.resource.attribute_enumerator.to_h)
        PROBE
      end

      it 'installs the trace SDK in place of the no-op tracer' do
        expect(booted['provider']).to eq('OpenTelemetry::SDK::Trace::TracerProvider')
        expect(booted['recording']).to be(true)
      end

      it 'labels every span with the service and deployment it came from' do
        expect(booted).to include(
          'service.name' => Observability::SERVICE_NAME,
          'service.version' => Observability::SERVICE_VERSION,
          'deployment.environment' => 'test'
        )
      end
    end

    context 'when the app queries the database it connected at boot' do
      let(:probe) do
        <<~PROBE
          DB['SELECT 1'].all
          { 'db_span_kinds' => exporter.finished_spans.map(&:kind).map(&:to_s) }
        PROBE
      end

      it 'traces the query, so the pg patch landed before the connection pool' do
        expect(booted['db_span_kinds']).to include('client')
      end
    end

    context 'with the instrumentation the app depends on' do
      let(:probe) do
        <<~PROBE
          {
            'installed' => %w[GraphQL PG Redis Resque].select do |name|
              OpenTelemetry::Instrumentation.const_get(name)::Instrumentation.instance.installed?
            end,
            'force_flush' =>
              OpenTelemetry::Instrumentation::Resque::Instrumentation.instance.config[:force_flush].to_s
          }
        PROBE
      end

      it 'patches every client the app actually uses' do
        expect(booted['installed']).to eq(%w[GraphQL PG Redis Resque])
      end

      it 'pins Resque to flush spans before its forked child exits' do
        # That child ends with `exit!`, which skips the at_exit hook that would
        # otherwise drain whatever the batch processor still holds.
        expect(booted['force_flush']).to eq('ask_the_job')
      end
    end
  end
end
