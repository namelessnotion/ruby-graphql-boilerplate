# frozen_string_literal: true
# typed: false

RSpec.describe Mutations::UpdateNote, :aggregate_failures do
  def execute(id:, note: nil, due_at: nil)
    AppSchema.execute(
      'mutation($id: ID!, $noteAttributes: NoteAttributesInput!) {
        updateNote(id: $id, noteAttributes: $noteAttributes) { note { id note dueAt } }
      }',
      variables: { id: id, noteAttributes: { note: note, dueAt: due_at } }
    ).to_h
  end

  it 'updates the note text and returns it' do
    note = Note.create(note: 'remember the milk')

    result = execute(id: note.id.to_s, note: 'buy milk')

    saved = result.dig('data', 'updateNote', 'note')
    expect(saved['note']).to eq('buy milk')
    expect(Note[note.id].note).to eq('buy milk')
  end

  it 'updates the due_at and returns it' do
    note = Note.create(note: 'remember the milk')
    due_at = Time.now + 3600

    result = execute(id: note.id.to_s, due_at: due_at.iso8601)

    saved = result.dig('data', 'updateNote', 'note')
    expect(Time.iso8601(saved['dueAt'])).to be_within(1).of(due_at)
    expect(Note[note.id].due_at).to be_within(1).of(due_at)
  end

  it 'leaves fields unchanged when not provided' do
    note = Note.create(note: 'remember the milk')

    result = execute(id: note.id.to_s)

    saved = result.dig('data', 'updateNote', 'note')
    expect(saved['note']).to eq('remember the milk')
  end

  it 'returns a GraphQL error instead of raising when the note does not exist' do
    result = execute(id: '-1', note: 'buy milk')

    expect(result['errors']).to include(a_hash_including('message' => 'note not found'))
    expect(result.dig('data', 'updateNote')).to be_nil
  end

  it 'returns a GraphQL error instead of raising when the note text is blank' do
    note = Note.create(note: 'remember the milk')

    result = execute(id: note.id.to_s, note: '')

    expect(result['errors']).to include(a_hash_including('message' => 'note is not present'))
    expect(result.dig('data', 'updateNote')).to be_nil
  end

  it 'returns a GraphQL error instead of raising when the due_at is in the past' do
    note = Note.create(note: 'remember the milk')

    result = execute(id: note.id.to_s, due_at: (Time.now - 3600).iso8601)

    expect(result['errors']).to include(a_hash_including('message' => 'due_at must be in the future'))
    expect(result.dig('data', 'updateNote')).to be_nil
  end
end
