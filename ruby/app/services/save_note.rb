# frozen_string_literal: true
# typed: strict

require_relative 'base_service'

module Services
  # Persists a new Note via the Note model.
  class SaveNote < BaseService
    extend T::Sig

    sig { params(note: String).void }
    def initialize(note:)
      super()
      @note = T.let(note, String)
    end

    sig { returns(Note) }
    def call
      perform { Note.create(note: @note) }
    end
  end
end
