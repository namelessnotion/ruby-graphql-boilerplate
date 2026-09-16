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

    field :notes, NoteType.connection_type, null: false, description: 'All notes, excluding archived ones.',
                                            max_page_size: 25

    field :note, NoteType, null: true,
                           description: 'A single note by id, or null when none exists or it is archived.' do
      argument :id, ID, required: true, description: 'The note id.'
    end

    sig { returns(T::Boolean) }
    def ok?
      true
    end

    sig { returns(Sequel::Dataset) }
    def notes
      Note.dataset.exclude(state: 'archived').order(:id)
    end

    sig { params(id: String).returns(T.nilable(Note)) }
    def note(id:)
      Note.exclude(state: 'archived').first(id: Integer(id))
    rescue ArgumentError
      nil
    end
  end
end
