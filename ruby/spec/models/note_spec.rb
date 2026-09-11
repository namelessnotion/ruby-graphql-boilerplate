# frozen_string_literal: true
# typed: false

RSpec.describe Note, 'validations' do
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

RSpec.describe Note, 'persistence' do
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

  it 'round-trips through the notes table' do
    created = described_class.create(note: 'round trip')

    reloaded = described_class.dataset.where(id: created.id).first

    expect(reloaded[:note]).to eq('round trip')
  end
end
