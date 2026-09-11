# frozen_string_literal: true
# typed: strict

require_relative 'objects/base_object'
require_relative '../mutations/save_note'

module Types
  # Root Mutation type
  class MutationType < BaseObject
    field :save_note, mutation: Mutations::SaveNote
  end
end
