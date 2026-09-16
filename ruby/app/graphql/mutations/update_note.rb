# frozen_string_literal: true
# typed: strict

require_relative 'base_mutation'
require_relative '../types/inputs/note_attributes_input'
require_relative '../types/objects/note_type'

module Mutations
  # Updates a Note's content and due date via Services::UpdateNote
  class UpdateNote < BaseMutation
    description "Updates a note's content and due date."

    argument :id, ID, required: true, description: 'The note id.'
    argument :note_attributes, Types::Inputs::NoteAttributesInput, required: true,
                                                                   description: 'The attributes to update.'

    field :note, Types::NoteType, null: false, description: 'The updated note.'

    sig { params(id: String, note_attributes: Types::Inputs::NoteAttributesInput).returns(T::Hash[Symbol, Note]) }
    def resolve(id:, note_attributes:)
      {
        note: Services::UpdateNote.new(
          id: id.to_i,
          note: note_attributes.note,
          due_at: note_attributes.due_at
        ).call
      }
    end
  end
end
