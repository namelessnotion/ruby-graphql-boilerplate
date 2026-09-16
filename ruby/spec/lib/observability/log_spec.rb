# frozen_string_literal: true
# typed: false

require 'stringio'

RSpec.describe Observability::Log, :aggregate_failures do
  # The real logger writes to $stdout, which it captures when it is built.
  # These examples drive an equivalent logger over a StringIO so the emitted
  # line can be read back; the formatter under test is the production one.
  let(:device) { StringIO.new }
  let(:logger) { Logger.new(device, level: Logger::DEBUG, formatter: Observability::Log::Formatter.new) }

  def logged_entries
    device.string.each_line.map { |line| JSON.parse(line) }
  end

  describe described_class::Formatter do
    it 'emits one JSON object per line' do
      logger.info('note saved')
      logger.warn('note not found')

      expect(logged_entries.map { |entry| entry['message'] }).to eq(['note saved', 'note not found'])
    end

    it 'stamps the level, an ISO-8601 UTC timestamp, and the service name' do
      logger.info('note saved')

      entry = logged_entries.first
      expect(entry['level']).to eq('INFO')
      expect(entry['service.name']).to eq(Observability::SERVICE_NAME)
      expect { Time.iso8601(entry['timestamp']) }.not_to raise_error
      expect(entry['timestamp']).to end_with('Z')
    end

    it 'merges the extra fields of a structured message' do
      logger.error({ 'message' => 'unhandled exception', 'exception.type' => 'ArgumentError' })

      expect(logged_entries.first).to include(
        'level' => 'ERROR',
        'message' => 'unhandled exception',
        'exception.type' => 'ArgumentError'
      )
    end

    context 'when a span is in scope' do
      include_context 'with recorded spans'

      it 'correlates the line with that span' do
        Observability.in_span('test.operation') { logger.info('note saved') }

        span = recorded_span_named('test.operation')
        expect(logged_entries.first).to include(
          'trace_id' => span.hex_trace_id,
          'span_id' => span.hex_span_id
        )
      end
    end

    context 'when no span is in scope' do
      it 'omits the correlation fields rather than writing invalid ids' do
        logger.info('note saved')

        expect(logged_entries.first.keys).not_to include('trace_id', 'span_id')
      end
    end
  end

  describe '.logger' do
    it 'is a stdlib Logger using the JSON formatter' do
      expect(described_class.logger).to be_a(Logger)
      expect(described_class.logger.formatter).to be_a(Observability::Log::Formatter)
    end

    it 'takes its level from LOG_LEVEL' do
      expect(described_class.logger.level).to eq(Logger::FATAL)
    end
  end

  describe 'level helpers' do
    it 'forwards the message and any extra fields to the logger' do
      allow(described_class).to receive(:logger).and_return(logger)

      described_class.error('unhandled exception', 'exception.type' => 'ArgumentError')

      expect(logged_entries.first).to include(
        'level' => 'ERROR',
        'message' => 'unhandled exception',
        'exception.type' => 'ArgumentError'
      )
    end
  end
end
