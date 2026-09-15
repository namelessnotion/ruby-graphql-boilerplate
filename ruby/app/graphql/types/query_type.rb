# frozen_string_literal: true
# typed: strict

require_relative 'objects/base_object'
require_relative 'objects/note_type'

module Types
  # Root Query type.
  class QueryType < BaseObject
    description 'The root query type.'

    field :ok, Boolean, null: false, resolver_method: :ok?,
                        description: 'Health check placeholder until real queries exist.'

    field :notes, NoteType.connection_type, null: false, description: 'All notes.', max_page_size: 25

    sig { returns(T::Boolean) }
    def ok?
      true
    end

    sig { returns(Sequel::Dataset) }
    def notes
      Note.dataset.order(:id)
    end
  end
end
