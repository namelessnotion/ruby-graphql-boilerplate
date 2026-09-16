# frozen_string_literal: true
# typed: strict

require_relative 'base_service'

module Services
  # Updates a Note's content and due date via the Note model.
  class UpdateNote < BaseService
    sig { params(id: Integer, note: T.nilable(String), due_at: T.nilable(Time)).void }
    def initialize(id:, note: nil, due_at: nil)
      super()
      @id = T.let(id, Integer)
      @note = T.let(note, T.nilable(String))
      @due_at = T.let(due_at, T.nilable(Time))
    end

    sig { returns(Note) }
    def call
      perform do
        record = Note.with_pk!(@id)
        record.note = @note unless @note.nil?
        record.due_at = @due_at unless @due_at.nil?
        record.save_changes
        record
      end
    end
  end
end
