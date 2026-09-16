# frozen_string_literal: true
# typed: false

require 'roda'
require_relative '../../request_tracing'
require_relative '../../services/save_note'

module Api
  module V1
    # /api/v1/notes — mounted by Api::V1::App.
    class Notes < Roda
      include RequestTracing

      plugin :all_verbs
      plugin :json
      plugin :json_parser, content_type_regexp: %r{\Aapplication/json\b}i

      # See Api::App — each Roda app needs its own handler, since a nested app
      # that handles its own errors never lets them reach its parent.
      plugin :error_handler do |e|
        log_unhandled(request, e)
        response.status = 500
        { errors: ['internal server error'] }
      end

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
        text = params['note']
        # Services::SaveNote's sig only accepts a String; a missing or
        # non-string `note` is a client error, not a 500.
        return unprocessable('note is not present') unless text.is_a?(String)

        note = Services::SaveNote.new(note: text).call
        response.status = 201
        response['location'] = "/api/v1/notes/#{note.id}"
        serialize(note)
      rescue Sequel::ValidationFailed => e
        unprocessable(e.message)
      end

      def show_note(id)
        note = Note[id]
        return serialize(note) if note

        response.status = 404
        { errors: ['note not found'] }
      end

      def unprocessable(message)
        response.status = 422
        { errors: [message] }
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
