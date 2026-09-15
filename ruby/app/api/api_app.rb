# frozen_string_literal: true
# typed: false

require 'roda'
require_relative 'v1/app'

module Api
  # RESTful API mounted at /api by App
  # Routes are versioned — /api/v1 dispatches to Api::V1::App
  # CORS preflight is handled once here for the whole /api surface.
  class App < Roda
    plugin :all_verbs
    plugin :json

    route do |r|
      r.options { cors_preflight }

      r.on('v1') { r.run Api::V1::App }

      not_found
    end

    private

    def cors_preflight
      response.status = 204
      response['access-control-allow-methods'] = 'GET, POST, PATCH, DELETE, OPTIONS'
      response['access-control-allow-headers'] = 'Content-Type'
      ''
    end

    def not_found
      response.status = 404
      { errors: ['not found'] }
    end
  end
end
