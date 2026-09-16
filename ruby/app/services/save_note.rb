# frozen_string_literal: true
# typed: strict

require_relative 'base_service'

module Services
  # Persists a new Note via the Note model.
  class SaveNote < BaseService
    sig { params(note: String, due_at: T.nilable(Time)).void }
    def initialize(note:, due_at: nil)
      super()
      @note = T.let(note, String)
      @due_at = T.let(due_at, T.nilable(Time))
    end

    sig { returns(Note) }
    def call
      perform { Note.create(note: @note, due_at: @due_at) }
    end
  end
end
