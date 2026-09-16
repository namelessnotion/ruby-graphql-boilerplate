# frozen_string_literal: true
# typed: false

require 'roda'
require_relative 'notes'

module Api
  module V1
    # Mounted at /api/v1 by Api::App.
    class App < Roda
      plugin :json

      # See Api::App — each Roda app needs its own handler, since a nested app
      # that handles its own errors never lets them reach its parent.
      plugin :error_handler do |_e|
        response.status = 500
        { errors: ['internal server error'] }
      end

      route do |r|
        r.on('notes') { r.run Api::V1::Notes }

        not_found
      end

      private

      def not_found
        response.status = 404
        { errors: ['not found'] }
      end
    end
  end
end
