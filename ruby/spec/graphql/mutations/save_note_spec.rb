# frozen_string_literal: true
# typed: false

RSpec.describe Mutations::SaveNote, :aggregate_failures do
  def execute(note:, due_at: nil)
    AppSchema.execute(
      'mutation($note: String!, $dueAt: ISO8601DateTime) {
        saveNote(note: $note, dueAt: $dueAt) { note { id note dueAt createdAt updatedAt } }
      }',
      variables: { note: note, dueAt: due_at&.iso8601 }
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

  it 'persists a note with a due_at' do
    due_at = Time.now + 3600
    result = execute(note: 'remember the milk', due_at:)

    saved = result.dig('data', 'saveNote', 'note')
    expect(Time.iso8601(saved['dueAt'])).to be_within(1).of(due_at)
    expect(Note[saved['id'].to_i].due_at).to be_within(1).of(due_at)
  end

  it 'returns a GraphQL error instead of raising when the due_at is in the past' do
    result = execute(note: 'remember the milk', due_at: Time.now - 3600)

    expect(result['errors']).to include(a_hash_including('message' => 'due_at must be in the future'))
    expect(result.dig('data', 'saveNote')).to be_nil
  end
end
