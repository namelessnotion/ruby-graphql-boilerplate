# frozen_string_literal: true
# typed: false

RSpec.describe Services::ArchiveNote, :aggregate_failures do
  it 'transitions the note to archived from pending' do
    note = Note.create(note: 'remember the milk')

    result = described_class.new(id: note.id).call

    expect(result.state).to eq('archived')
    expect(Note[note.id].state).to eq('archived')
  end

  it 'transitions the note to archived from completed' do
    note = Note.create(note: 'remember the milk')
    note.must_process(:complete)

    result = described_class.new(id: note.id).call

    expect(result.state).to eq('archived')
  end

  it 'raises when the note does not exist' do
    expect { described_class.new(id: -1).call }.to raise_error(Sequel::NoMatchingRow)
  end

  it 'raises when the note is already archived' do
    note = Note.create(note: 'remember the milk')
    note.must_process(:archive)

    expect { described_class.new(id: note.id).call }
      .to raise_error(StateMachines::Sequel::FailedTransition, /failed to transition on archive/)
    expect(Note[note.id].state).to eq('archived')
  end
end
