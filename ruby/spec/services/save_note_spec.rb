# frozen_string_literal: true
# typed: false

RSpec.describe Services::SaveNote, :aggregate_failures do
  it 'persists a note via the Note model' do
    note = described_class.new(note: 'remember the milk').call

    expect(note).to be_a(Note)
    expect(note.new?).to be(false)
    expect(Note[note.id].note).to eq('remember the milk')
  end

  it 'raises when the note is blank' do
    expect { described_class.new(note: '').call }.to raise_error(Sequel::ValidationFailed)
  end

  it 'does not persist a note when validation fails' do
    expect { described_class.new(note: '').call }
      .to raise_error(Sequel::ValidationFailed)
      .and not_change(Note, :count)
  end

  it 'persists a note with a due_at' do
    due_at = Time.now + 3600
    note = described_class.new(note: 'remember the milk', due_at:).call

    expect(note.due_at).to be_within(1).of(due_at)
  end

  it 'raises when the due_at is in the past' do
    expect { described_class.new(note: 'remember the milk', due_at: Time.now - 3600).call }
      .to raise_error(Sequel::ValidationFailed)
  end
end
