# frozen_string_literal: true
# typed: false

require 'opentelemetry/sdk'

RSpec.describe Observability, :aggregate_failures do
  # Resque forks a child per job and ends it with `exit!`, which skips the
  # at_exit hook the SDK installs to drain buffered spans. That is why
  # configure! pins the Resque instrumentation's :force_flush rather than
  # leaving it implicit — and this is the guarantee the pinning rests on: a
  # batch processor inherited across a fork still exports from the child,
  # provided something flushes it before the child goes away.
  describe 'spans recorded in a forked worker' do
    let(:span_exporter) { OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new }

    let(:provider) do
      OpenTelemetry::SDK::Trace::TracerProvider.new.tap do |tracer_provider|
        # A batch processor specifically: its export thread is the part that
        # does not survive the fork.
        tracer_provider.add_span_processor(
          OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(span_exporter)
        )
      end
    end

    def fork_writing_to(writer)
      fork do
        writer.puts(yield)
      ensure
        writer.close
        # Mirrors how Resque ends a job's child process.
        exit!(0)
      end
    end

    # Runs the block in a forked child and returns whatever it wrote back.
    def in_forked_child(&)
      reader, writer = IO.pipe
      pid = fork_writing_to(writer, &)
      writer.close

      output = reader.read
      Process.wait(pid)
      reader.close
      output
    end

    it 'reach the exporter once the child flushes them' do
      # Built before the fork, so the child inherits a processor whose export
      # thread died in it.
      inherited = provider

      exported = in_forked_child do
        inherited.tracer('stack').in_span('job.perform') { nil }
        inherited.force_flush
        span_exporter.finished_spans.map(&:name)
      end

      expect(exported).to include('job.perform')
    end
  end
end
