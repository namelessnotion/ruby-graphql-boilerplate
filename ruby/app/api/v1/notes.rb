# frozen_string_literal: true
# typed: false

require 'roda'
require_relative '../../services/save_note'

module Api
  module V1
    # /api/v1/notes — mounted by Api::V1::App.
    class Notes < Roda
      plugin :all_verbs
      plugin :json
      plugin :json_parser, content_type_regexp: %r{\Aapplication/json\b}i

      route do |r|
        r.is do
          r.get { list_notes }
          r.post { create_note(r.params) }
        end

        r.is Integer do |id|
          r.get { show_note(id) }
        end
      end

      private

      def list_notes
        Note.dataset.order(:id).map { |note| serialize(note) }
      end

      def create_note(params)
        note = Services::SaveNote.new(note: params['note']).call
        response.status = 201
        response['location'] = "/api/v1/notes/#{note.id}"
        serialize(note)
      rescue Sequel::ValidationFailed => e
        response.status = 422
        { errors: [e.message] }
      end

      def show_note(id)
        note = Note[id]
        return serialize(note) if note

        response.status = 404
        { errors: ['note not found'] }
      end

      def serialize(note)
        {
          id: note.id,
          note: note.note,
          created_at: note.created_at,
          updated_at: note.updated_at
        }
      end
    end
  end
end
