# frozen_string_literal: true
# typed: strict

require_relative 'base_input_object'

module Types
  module Inputs
    # GraphQL input type for the updatable attributes of a Note
    class NoteAttributesInput < BaseInputObject
      description 'Attributes to update on a note.'

      argument :due_at, GraphQL::Types::ISO8601DateTime, required: false, description: 'When the note is due.'
      argument :note, String, required: false, description: 'The note text.'
    end
  end
end
