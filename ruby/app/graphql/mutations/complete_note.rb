# frozen_string_literal: true
# typed: strict

require_relative 'base_mutation'
require_relative '../types/objects/note_type'

module Mutations
  # Transitions a Note to completed via Services::CompleteNote
  class CompleteNote < BaseMutation
    description 'Marks a note as completed.'

    argument :id, ID, required: true, description: 'The note id.'

    field :note, Types::NoteType, null: false, description: 'The updated note.'

    sig { params(id: String).returns(T::Hash[Symbol, Note]) }
    def resolve(id:)
      { note: Services::CompleteNote.new(id: id.to_i).call }
    end
  end
end
