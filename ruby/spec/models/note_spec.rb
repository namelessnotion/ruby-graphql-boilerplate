# frozen_string_literal: true
# typed: false

require 'state_machines/sequel/spec_helpers'

RSpec.describe Note, :aggregate_failures do
  describe '#valid?' do
    it 'is valid with a note' do
      note = described_class.new(note: 'remember the milk')

      expect(note).to be_valid
    end

    it 'is invalid without a note' do
      note = described_class.new(note: nil)

      expect(note).not_to be_valid
      expect(note.errors[:note]).to include('is not present')
    end

    it 'is invalid with a blank note' do
      note = described_class.new(note: '')

      expect(note).not_to be_valid
      expect(note.errors[:note]).to include('is not present')
    end
  end

  describe '#state' do
    it 'starts pending' do
      note = described_class.create(note: 'remember the milk')

      expect(note.state).to eq('pending')
      expect(note.pending?).to be(true)
    end
  end

  describe '#complete' do
    it_behaves_like 'a state machine with audit logging', :complete, 'completed' do
      let(:machine) { described_class.create(note: 'remember the milk') }
    end

    it 'transitions from pending to completed' do
      note = described_class.create(note: 'remember the milk')

      expect(note).to transition_on(:complete).to('completed')
      expect(note.completed?).to be(true)
    end

    it 'does not allow completing an already-completed note' do
      note = described_class.create(note: 'remember the milk')
      note.complete!

      expect(note).to not_transition_on(:complete)
      expect(note.state).to eq('completed')
    end
  end

  describe '#willnotdo' do
    it 'transitions from pending to willnotdo' do
      note = described_class.create(note: 'remember the milk')

      expect(note).to transition_on(:willnotdo).to('willnotdo')
      expect(note.willnotdo?).to be(true)
    end
  end

  describe '#archive' do
    it_behaves_like 'a state machine with audit logging', :archive, 'archived' do
      let(:machine) { described_class.create(note: 'remember the milk') }
    end

    it 'archives from any of pending, completed, or willnotdo' do
      note = described_class.create(note: 'remember the milk')
      note.complete!

      expect(note).to transition_on(:archive).to('archived')
      expect(note.archived?).to be(true)
    end
  end

  describe '#process' do
    it 'persists state across a reload' do
      note = described_class.create(note: 'remember the milk')
      note.process(:complete)

      expect(described_class[note.id].state).to eq('completed')
    end
  end

  describe '#completed_at' do
    it 'is set when the note transitions to completed' do
      note = described_class.create(note: 'remember the milk')

      expect(note.completed_at).to be_nil

      note.complete!

      expect(note.completed_at).to be_a(Time)
    end
  end

  describe '#archived_at' do
    it 'is set when the note transitions to archived' do
      note = described_class.create(note: 'remember the milk')
      note.complete!

      expect(note.archived_at).to be_nil

      note.archive!

      expect(note.archived_at).to be_a(Time)
    end
  end

  describe '.create' do
    it 'saves a valid note to the database' do
      note = described_class.create(note: 'buy groceries')

      expect(note.new?).to be(false)
      expect(described_class[note.id].note).to eq('buy groceries')
    end

    it 'raises when saving an invalid note' do
      expect { described_class.create(note: nil) }.to raise_error(Sequel::ValidationFailed)
    end

    it 'stamps created_at and updated_at on save' do
      note = described_class.create(note: 'timestamped')

      expect(note.created_at).not_to be_nil
      expect(note.updated_at).not_to be_nil
    end
  end

  describe '.dataset' do
    it 'round-trips through the notes table' do
      created = described_class.create(note: 'round trip')

      reloaded = described_class.dataset.where(id: created.id).first

      expect(reloaded[:note]).to eq('round trip')
    end
  end
end
