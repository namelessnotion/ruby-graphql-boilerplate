# frozen_string_literal: true
# typed: strict

require_relative 'base_object'

module Types
  # GraphQL type for a Note
  class NoteType < BaseObject
    field :id, ID, null: false
    field :note, String, null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
  end
end
