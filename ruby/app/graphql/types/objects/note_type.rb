# frozen_string_literal: true
# typed: strict

require_relative 'base_object'

module Types
  # GraphQL type for a Note
  class NoteType < BaseObject
    description 'A persisted note.'

    field :created_at, GraphQL::Types::ISO8601DateTime, null: false, description: 'When the note was created.'
    field :due_at, GraphQL::Types::ISO8601DateTime, null: true, description: 'When the note is due.'
    field :id, ID, null: false, description: 'The note id.'
    field :note, String, null: false, description: 'The note text.'
    field :state, String, null: false, description: 'The note state.'
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false, description: 'When the note was last updated.'
  end
end
