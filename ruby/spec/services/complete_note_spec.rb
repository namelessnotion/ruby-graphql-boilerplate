# frozen_string_literal: true
# typed: false

RSpec.describe Services::CompleteNote, :aggregate_failures do
  it 'transitions the note to completed' do
    note = Note.create(note: 'remember the milk')

    result = described_class.new(id: note.id).call

    expect(result.state).to eq('completed')
    expect(Note[note.id].state).to eq('completed')
  end

  it 'raises when the note does not exist' do
    expect { described_class.new(id: -1).call }.to raise_error(Sequel::NoMatchingRow)
  end

  it 'raises when the note is already completed' do
    note = Note.create(note: 'remember the milk')
    note.must_process(:complete)

    expect { described_class.new(id: note.id).call }
      .to raise_error(StateMachines::Sequel::FailedTransition, /failed to transition on complete/)
    expect(Note[note.id].state).to eq('completed')
  end
end
