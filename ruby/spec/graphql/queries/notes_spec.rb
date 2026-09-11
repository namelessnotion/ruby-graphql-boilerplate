# frozen_string_literal: true
# typed: false

RSpec.describe 'notes query' do
  def execute
    AppSchema.execute(<<~GQL).to_h
      query {
        notes {
          edges {
            node { id note createdAt updatedAt }
          }
        }
      }
    GQL
  end

  it 'returns all notes' do
    first = Note.create(note: 'first note')
    second = Note.create(note: 'second note')

    nodes = execute.dig('data', 'notes', 'edges').map { |edge| edge['node'] }

    expect(nodes.map { |node| node['id'].to_i }).to contain_exactly(first.id, second.id)
    expect(nodes.map { |node| node['note'] }).to contain_exactly('first note', 'second note')
  end

  it 'returns an empty list when there are no notes' do
    expect(execute.dig('data', 'notes', 'edges')).to eq([])
  end
end
