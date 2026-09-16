# frozen_string_literal: true
# typed: false

RSpec.describe 'note query', :aggregate_failures do
  def execute(id)
    AppSchema.execute(<<~GQL, variables: { 'id' => id }).to_h
      query($id: ID!) {
        note(id: $id) { id note state createdAt updatedAt }
      }
    GQL
  end

  it 'returns the note with the given id' do
    note = Note.create(note: 'first note')
    Note.create(note: 'second note')

    result = execute(note.id).dig('data', 'note')

    expect(result['id'].to_i).to eq(note.id)
    expect(result['note']).to eq('first note')
    expect(result['state']).to eq('pending')
  end

  it 'returns null when no note has that id' do
    result = execute(0)

    expect(result['data']['note']).to be_nil
    expect(result['errors']).to be_nil
  end

  it 'returns null when the id is not a number' do
    result = execute('not-an-id')

    expect(result['data']['note']).to be_nil
    expect(result['errors']).to be_nil
  end

  it 'returns null for an archived note, which is soft-deleted' do
    note = Note.create(note: 'first note')
    note.must_process(:archive)

    result = execute(note.id)

    expect(result['data']['note']).to be_nil
    expect(result['errors']).to be_nil
  end
end
