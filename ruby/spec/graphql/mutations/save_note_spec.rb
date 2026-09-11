# frozen_string_literal: true
# typed: false

RSpec.describe Mutations::SaveNote do
  def execute(note:)
    AppSchema.execute(
      'mutation($note: String!) { saveNote(note: $note) { note { id note createdAt updatedAt } } }',
      variables: { note: note }
    ).to_h
  end

  it 'persists a note via Services::SaveNote and returns it' do
    result = execute(note: 'remember the milk')

    saved = result.dig('data', 'saveNote', 'note')
    expect(saved['note']).to eq('remember the milk')
    expect(saved['createdAt']).not_to be_nil
    expect(saved['updatedAt']).not_to be_nil
    expect(Note[saved['id'].to_i].note).to eq('remember the milk')
  end

  it 'returns a GraphQL error instead of raising when the note is blank' do
    result = execute(note: '')

    expect(result['errors']).to include(a_hash_including('message' => 'note is not present'))
    expect(result.dig('data', 'saveNote')).to be_nil
  end
end
