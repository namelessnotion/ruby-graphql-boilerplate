# frozen_string_literal: true
# typed: false

RSpec.describe Mutations::CompleteNote, :aggregate_failures do
  def execute(id:)
    AppSchema.execute(
      'mutation($id: ID!) { completeNote(id: $id) { note { id state } } }',
      variables: { id: id }
    ).to_h
  end

  it 'transitions the note to completed and returns it' do
    note = Note.create(note: 'remember the milk')

    result = execute(id: note.id.to_s)

    saved = result.dig('data', 'completeNote', 'note')
    expect(saved['state']).to eq('completed')
    expect(Note[note.id].state).to eq('completed')
  end

  it 'returns a GraphQL error instead of raising when the note does not exist' do
    result = execute(id: '-1')

    expect(result['errors']).to include(a_hash_including('message' => 'note not found'))
    expect(result.dig('data', 'completeNote')).to be_nil
  end

  it 'returns a GraphQL error instead of raising when the transition is invalid' do
    note = Note.create(note: 'remember the milk')
    note.must_process(:complete)

    result = execute(id: note.id.to_s)

    expect(result['errors'])
      .to include(a_hash_including('message' => a_string_matching(/failed to transition on complete/)))
    expect(result.dig('data', 'completeNote')).to be_nil
  end
end
