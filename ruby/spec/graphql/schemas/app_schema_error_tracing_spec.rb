# frozen_string_literal: true
# typed: false

RSpec.describe AppSchema, :aggregate_failures do
  include_context 'with recorded spans'

  def exception_events
    recorded_span_named('graphql.request').events.select { |event| event.name == 'exception' }
  end

  def execute(query, variables = {})
    Observability.in_span('graphql.request') do
      AppSchema.execute(query, variables: variables).to_h
    end
  end

  describe 'a persistence error translated by rescue_from' do
    it 'records Sequel::NoMatchingRow on the span in scope' do
      result = execute('mutation($id: ID!) { completeNote(id: $id) { note { id } } }', { id: '-1' })

      expect(result['errors']).to include(a_hash_including('message' => 'note not found'))
      expect(exception_events.first.attributes).to include('exception.type' => 'Sequel::NoMatchingRow')
    end

    it 'records Sequel::ValidationFailed on the span in scope' do
      result = execute('mutation($note: String!) { saveNote(note: $note) { note { id } } }', { note: '' })

      expect(result['errors']).to include(a_hash_including('message' => 'note is not present'))
      expect(exception_events.first.attributes).to include('exception.type' => 'Sequel::ValidationFailed')
    end

    it 'records a failed state-machine transition on the span in scope' do
      note = Note.create(note: 'remember the milk')
      note.must_process(:complete)

      result = execute('mutation($id: ID!) { completeNote(id: $id) { note { id } } }', { id: note.id.to_s })

      expect(result['errors']).not_to be_empty
      expect(exception_events.first.attributes)
        .to include('exception.type' => 'StateMachines::Sequel::FailedTransition')
    end

    it 'leaves the span status unset, since these are client errors' do
      execute('mutation($id: ID!) { completeNote(id: $id) { note { id } } }', { id: '-1' })

      expect(recorded_span_named('graphql.request').status.code)
        .not_to eq(OpenTelemetry::Trace::Status::ERROR)
    end
  end

  describe '.resource_name' do
    def error_for(dataset)
      error = Sequel::NoMatchingRow.new
      error.dataset = dataset
      error
    end

    it 'derives the resource name from the dataset that raised the error, not a hardcoded string' do
      expect(described_class.send(:resource_name, error_for(Note.dataset))).to eq('note')
    end

    it 'snake_cases a multi-word model name, so this generalizes past single-word resources' do
      fake_model = stub_const('PurchaseOrder', Class.new)

      expect(described_class.send(:resource_name, error_for(double(model: fake_model)))).to eq('purchase_order')
    end

    it 'falls back to a generic label when the dataset has no associated model' do
      expect(described_class.send(:resource_name, error_for(double))).to eq('record')
    end
  end
end
