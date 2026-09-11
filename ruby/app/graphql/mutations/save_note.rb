# frozen_string_literal: true
# typed: strict

require_relative 'base_mutation'
require_relative '../types/objects/note_type'

module Mutations
  # Persists a new Note via Services::SaveNote.
  class SaveNote < BaseMutation
    argument :note, String, required: true, description: 'The note text to save.'

    field :note, Types::NoteType, null: false, description: 'The saved note.'

    sig { params(note: String).returns(T::Hash[Symbol, Note]) }
    def resolve(note:)
      { note: Services::SaveNote.new(note:).call }
    rescue Sequel::ValidationFailed => e
      raise GraphQL::ExecutionError, e.message
    end
  end
end
