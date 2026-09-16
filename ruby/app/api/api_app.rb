# frozen_string_literal: true
# typed: false

require 'roda'
require_relative '../request_tracing'
require_relative 'v1/app'

module Api
  # RESTful API mounted at /api by App
  # Routes are versioned — /api/v1 dispatches to Api::V1::App
  # CORS preflight is handled once here for the whole /api surface.
  class App < Roda
    include RequestTracing

    plugin :all_verbs
    plugin :json

    # Anything escaping this surface answers with the REST error contract
    # ({ errors: [...] } and an explicit status) rather than a bare 500 from
    # the web server. The exception itself is deliberately not echoed back.
    plugin :error_handler do |e|
      log_unhandled(request, e)
      response.status = 500
      { errors: ['internal server error'] }
    end

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
