# frozen_string_literal: true
# typed: false

RSpec.describe Observability, :aggregate_failures do
  describe '.in_span' do
    include_context 'with recorded spans'

    it 'records a span under the given name with the given attributes' do
      described_class.in_span('test.operation', 'test.attribute' => 'value') { nil }

      span = recorded_span_named('test.operation')
      expect(span).not_to be_nil
      expect(span.attributes).to include('test.attribute' => 'value')
    end

    it 'returns whatever the block returned' do
      expect(described_class.in_span('test.operation') { :result }).to eq(:result)
    end

    it 'yields the span so a caller can attach attributes it only learns later' do
      described_class.in_span('test.operation') { |span| span.set_attribute('http.status_code', 200) }

      expect(recorded_span_named('test.operation').attributes).to include('http.status_code' => 200)
    end

    it 'sets the span kind when one is given' do
      described_class.in_span('test.operation', kind: :server) { nil }

      expect(recorded_span_named('test.operation').kind).to eq(:server)
    end

    it 'nests a span inside the span already in scope' do
      described_class.in_span('outer') { described_class.in_span('inner') { nil } }

      expect(recorded_span_named('inner').parent_span_id).to eq(recorded_span_named('outer').span_id)
    end

    it 'records a raised exception on the span, marks it failed, and re-raises' do
      expect { described_class.in_span('test.operation') { raise ArgumentError, 'boom' } }
        .to raise_error(ArgumentError, 'boom')

      span = recorded_span_named('test.operation')
      expect(span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
      expect(span.events.map(&:name)).to include('exception')
    end
  end

  describe '.in_span when the SDK is disabled' do
    # No recorded-spans context here on purpose: this is the path the suite
    # runs on by default (OTEL_SDK_DISABLED=true in .env.test) and the one
    # that has to keep working in CI with nothing running.
    it 'still yields and returns the block result' do
      yielded = false

      result = described_class.in_span('test.operation') do |span|
        yielded = true
        expect(span.recording?).to be(false)
        :result
      end

      expect([yielded, result]).to eq([true, :result])
    end

    it 'leaves no trace id for the logger to stamp' do
      described_class.in_span('test.operation') do
        expect(OpenTelemetry::Trace.current_span.context).not_to be_valid
      end
    end
  end

  describe '.continue_trace' do
    include_context 'with recorded spans'

    let(:trace_id) { 'a1b2c3d4e5f60718293a4b5c6d7e8f90' }
    let(:parent_span_id) { '0123456789abcdef' }
    let(:env) { { 'HTTP_TRACEPARENT' => "00-#{trace_id}-#{parent_span_id}-01" } }

    it 'continues a trace started by the caller' do
      described_class.continue_trace(env) { described_class.in_span('http.request') { nil } }

      span = recorded_span_named('http.request')
      expect(span.hex_trace_id).to eq(trace_id)
      expect(span.hex_parent_span_id).to eq(parent_span_id)
    end

    it 'starts a fresh trace when no traceparent was sent' do
      described_class.continue_trace({}) { described_class.in_span('http.request') { nil } }

      span = recorded_span_named('http.request')
      expect(span.hex_trace_id).not_to eq(trace_id)
      expect(span.parent_span_id).to eq(OpenTelemetry::Trace::INVALID_SPAN_ID)
    end

    it 'returns whatever the block returned' do
      expect(described_class.continue_trace(env) { :result }).to eq(:result)
    end
  end

  describe '.record_exception' do
    include_context 'with recorded spans'

    it 'attaches the exception to the span in scope' do
      described_class.in_span('test.operation') do
        described_class.record_exception(ArgumentError.new('boom'))
      end

      event = recorded_span_named('test.operation').events.find { |e| e.name == 'exception' }
      expect(event.attributes).to include('exception.type' => 'ArgumentError', 'exception.message' => 'boom')
    end

    it 'leaves the span status alone, so client errors do not read as failures' do
      described_class.in_span('test.operation') do
        described_class.record_exception(ArgumentError.new('boom'))
      end

      expect(recorded_span_named('test.operation').status.code).not_to eq(OpenTelemetry::Trace::Status::ERROR)
    end

    it 'is a no-op outside any span' do
      expect { described_class.record_exception(ArgumentError.new('boom')) }.not_to raise_error
    end
  end
end
