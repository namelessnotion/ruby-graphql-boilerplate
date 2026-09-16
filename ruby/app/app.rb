# frozen_string_literal: true
# typed: strict

require 'json'
require 'rack'
require_relative '../lib/environment'
require_relative 'request_tracing'

# `POST /graphql`, a `GET /healthz` liveness check, and the `/api` REST
# routes (see Api::App), all served through the same Rack app and Falcon
# process.
class App
  extend T::Sig
  # Brings in the server span around every request, and with it RackResponse.
  include RequestTracing

  API_MAP = T.let(Rack::URLMap.new('/api' => Api::App), Rack::URLMap)

  sig { params(env: T::Hash[String, T.untyped]).returns(RackResponse) }
  def call(env)
    request = Rack::Request.new(env)

    # Last line of defence: anything a surface fails to handle still answers
    # with JSON rather than a bare 500 from the web server. CORS headers are
    # still merged in below so the browser can actually read the body.
    status, headers, body = begin
      trace_request(request) { route(request) }
    rescue StandardError => e
      log_unhandled(request, e)
      internal_server_error
    end

    [status, headers.merge(cors_headers(request)), body]
  end

  private

  sig { params(request: Rack::Request).returns(RackResponse) }
  def route(request)
    case [request.request_method, request.path]
    in ['OPTIONS', '/graphql'] then preflight
    in ['GET', '/healthz'] then healthz
    in ['POST', '/graphql'] then graphql(request)
    in [_, path] if path.start_with?('/api') then api(request)
    else not_found
    end
  end

  sig { returns(String) }
  def allowed_origin
    ENV.fetch('CORS_ALLOWED_ORIGIN', 'http://localhost')
  end

  sig { params(request: Rack::Request).returns(T::Hash[String, String]) }
  def cors_headers(request)
    origin = request.get_header('HTTP_ORIGIN')
    return {} unless origin == allowed_origin

    { 'access-control-allow-origin' => origin, 'vary' => 'Origin' }
  end

  sig { returns(RackResponse) }
  def preflight
    [204, { 'access-control-allow-methods' => 'POST, OPTIONS', 'access-control-allow-headers' => 'Content-Type' }, []]
  end

  sig { returns(RackResponse) }
  def healthz
    json_response(200, status: 'ok')
  end

  sig { params(request: Rack::Request).returns(RackResponse) }
  def api(request)
    # Api::App (a Roda app) and Rack::URLMap have no Sorbet sigs of their
    # own, so this cast documents the Rack response contract they actually
    # honor at runtime.
    T.cast(API_MAP.call(request.env), RackResponse)
  end

  sig { params(request: Rack::Request).returns(RackResponse) }
  def graphql(request)
    payload = JSON.parse(request.body.read)

    if payload.is_a?(Array)
      multiplexed(payload)
    else
      single(payload)
    end
  rescue JSON::ParserError => e
    json_response(400, errors: [{ message: "invalid JSON: #{e.message}" }])
  end

  sig { params(payload: T::Hash[String, T.untyped]).returns(RackResponse) }
  def single(payload)
    result = AppSchema.execute(
      payload['query'],
      variables: payload['variables'] || {},
      operation_name: payload['operationName'],
      context: {}
    )

    json_response(200, result.to_h)
  end

  sig { params(payloads: T::Array[T.untyped]).returns(RackResponse) }
  def multiplexed(payloads)
    queries = payloads.map do |payload|
      {
        query: payload['query'],
        variables: payload['variables'] || {},
        operation_name: payload['operationName']
      }
    end

    results = AppSchema.multiplex(queries, context: {})

    json_response(200, results.map(&:to_h))
  end

  sig { returns(RackResponse) }
  def not_found
    json_response(404, errors: [{ message: 'not found' }])
  end

  sig { returns(RackResponse) }
  def internal_server_error
    json_response(500, errors: [{ message: 'internal server error' }])
  end

  sig { params(status: Integer, body: T.untyped).returns(RackResponse) }
  def json_response(status, body)
    [status, { 'content-type' => 'application/json' }, [JSON.generate(body)]]
  end
end
