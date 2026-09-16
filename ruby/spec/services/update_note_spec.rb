# frozen_string_literal: true
# typed: false

RSpec.describe Services::UpdateNote, :aggregate_failures do
  it 'updates the note text' do
    note = Note.create(note: 'remember the milk')

    result = described_class.new(id: note.id, note: 'buy milk').call

    expect(result.note).to eq('buy milk')
    expect(Note[note.id].note).to eq('buy milk')
  end

  it 'updates the due_at' do
    note = Note.create(note: 'remember the milk')
    due_at = Time.now + 3600

    result = described_class.new(id: note.id, due_at:).call

    expect(result.due_at).to be_within(1).of(due_at)
    expect(Note[note.id].due_at).to be_within(1).of(due_at)
  end

  it 'updates both note and due_at together' do
    note = Note.create(note: 'remember the milk')
    due_at = Time.now + 3600

    result = described_class.new(id: note.id, note: 'buy milk', due_at:).call

    expect(result.note).to eq('buy milk')
    expect(result.due_at).to be_within(1).of(due_at)
  end

  it 'leaves fields unchanged when not provided' do
    due_at = Time.now + 3600
    note = Note.create(note: 'remember the milk', due_at:)

    result = described_class.new(id: note.id).call

    expect(result.note).to eq('remember the milk')
    expect(result.due_at).to be_within(1).of(due_at)
  end

  it 'raises when the note does not exist' do
    expect { described_class.new(id: -1, note: 'x').call }.to raise_error(Sequel::NoMatchingRow)
  end

  it 'raises when the note text is blank' do
    note = Note.create(note: 'remember the milk')

    expect { described_class.new(id: note.id, note: '').call }.to raise_error(Sequel::ValidationFailed)
    expect(Note[note.id].note).to eq('remember the milk')
  end

  it 'raises when the due_at is in the past' do
    note = Note.create(note: 'remember the milk')

    expect { described_class.new(id: note.id, due_at: Time.now - 3600).call }
      .to raise_error(Sequel::ValidationFailed)
    expect(Note[note.id].due_at).to be_nil
  end
end
