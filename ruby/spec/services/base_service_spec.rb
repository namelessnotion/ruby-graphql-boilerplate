# frozen_string_literal: true
# typed: false

RSpec.describe Services::BaseService, :aggregate_failures do
  include_context 'with recorded spans'

  describe '#perform' do
    it 'wraps the write in a span named for the service that ran it' do
      Services::SaveNote.new(note: 'traced').call

      expect(recorded_span_named('Services::SaveNote')).not_to be_nil
    end

    it 'nests the service span inside whatever span is already in scope' do
      Observability.in_span('POST /api/v1/notes') { Services::SaveNote.new(note: 'traced').call }

      expect(recorded_span_named('Services::SaveNote').parent_span_id)
        .to eq(recorded_span_named('POST /api/v1/notes').span_id)
    end

    it 'still runs the block inside a transaction and returns its value' do
      note = Services::SaveNote.new(note: 'traced').call

      expect(note).to be_a(Note)
      expect(Note[note.id].note).to eq('traced')
    end

    it 'marks the span failed when the write raises' do
      expect { Services::SaveNote.new(note: '').call }.to raise_error(Sequel::ValidationFailed)

      expect(recorded_span_named('Services::SaveNote').status.code)
        .to eq(OpenTelemetry::Trace::Status::ERROR)
    end
  end
end
