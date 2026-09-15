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
end
