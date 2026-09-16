# frozen_string_literal: true
# typed: strict

require_relative 'objects/base_object'
require_relative '../mutations/archive_note'
require_relative '../mutations/complete_note'
require_relative '../mutations/save_note'
require_relative '../mutations/update_note'
require_relative '../mutations/willnotdo_note'

module Types
  # Root Mutation type
  class MutationType < BaseObject
    description 'The root mutation type.'

    field :archive_note, mutation: Mutations::ArchiveNote
    field :complete_note, mutation: Mutations::CompleteNote
    field :save_note, mutation: Mutations::SaveNote
    field :update_note, mutation: Mutations::UpdateNote
    field :willnotdo_note, mutation: Mutations::WillnotdoNote
  end
end
