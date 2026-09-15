# frozen_string_literal: true
# typed: false

require 'roda'
require_relative 'notes'

module Api
  module V1
    # Mounted at /api/v1 by Api::App.
    class App < Roda
      plugin :json

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
