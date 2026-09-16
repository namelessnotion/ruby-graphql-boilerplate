# frozen_string_literal: true
# typed: strict

require_relative 'base_service'

module Services
  # Transitions a Note to archived via the Note model.
  class ArchiveNote < BaseService
    sig { params(id: Integer).void }
    def initialize(id:)
      super()
      @id = T.let(id, Integer)
    end

    sig { returns(Note) }
    def call
      perform { Note.with_pk!(@id).must_process(:archive) }
    end
  end
end
