# frozen_string_literal: true
# typed: false

require 'rack/test'
require_relative '../../app/app'

RSpec.describe 'Request tracing', :aggregate_failures do
  include Rack::Test::Methods

  include_context 'with recorded spans'

  def app
    App.new
  end

  describe 'the server span' do
    it 'names the span by method and route and marks it a server span' do
      get '/healthz'

      span = recorded_span_named('GET /healthz')
      expect(span).not_to be_nil
      expect(span.kind).to eq(:server)
    end

    it 'records the request method, route, and response status' do
      get '/healthz'

      expect(recorded_span_named('GET /healthz').attributes).to include(
        'http.method' => 'GET',
        'http.route' => '/healthz',
        'http.status_code' => 200
      )
    end

    it 'records the status of a response the router did not match' do
      get '/nope'

      expect(recorded_span_named('GET /nope').attributes).to include('http.status_code' => 404)
    end

    it 'collapses record ids out of the route, so span names stay low-cardinality' do
      note = Services::SaveNote.new(note: 'traced').call

      get "/api/v1/notes/#{note.id}"

      expect(recorded_span_named('GET /api/v1/notes/:id')).not_to be_nil
    end

    it 'covers the GraphQL surface too' do
      post '/graphql', JSON.generate(query: '{ notes { nodes { id } } }'), 'CONTENT_TYPE' => 'application/json'

      expect(recorded_span_named('POST /graphql').attributes).to include('http.status_code' => 200)
    end
  end

  describe 'a trace that started in the browser' do
    let(:trace_id) { 'a1b2c3d4e5f60718293a4b5c6d7e8f90' }
    let(:parent_span_id) { '0123456789abcdef' }

    it 'continues into the API rather than starting a second trace' do
      get '/healthz', {}, 'HTTP_TRACEPARENT' => "00-#{trace_id}-#{parent_span_id}-01"

      span = recorded_span_named('GET /healthz')
      expect(span.hex_trace_id).to eq(trace_id)
      expect(span.hex_parent_span_id).to eq(parent_span_id)
    end

    it 'allows the browser to actually send the traceparent header, per the preflight response' do
      options '/graphql'

      expect(last_response.status).to eq(204)
      allowed_headers = last_response.headers['access-control-allow-headers'].split(',').map(&:strip)
      expect(allowed_headers).to include('Content-Type', 'traceparent')
    end
  end

  describe 'a 500 the REST surface handled itself' do
    # Api::V1::Notes' own error_handler catches this, so the server span never
    # sees the exception — only the status it answered with.
    before { allow(Note).to receive(:dataset).and_raise('boom') }

    it 'marks the server span failed on the status alone' do
      get '/api/v1/notes'

      expect(last_response.status).to eq(500)
      expect(recorded_span_named('GET /api/v1/notes').status.code)
        .to eq(OpenTelemetry::Trace::Status::ERROR)
    end

    it 'logs what actually broke, which the error contract does not tell the client' do
      allow(Observability::Log).to receive(:error)

      get '/api/v1/notes'

      expect(Observability::Log).to have_received(:error).with(
        'unhandled exception',
        hash_including('exception.type' => 'RuntimeError', 'exception.message' => 'boom')
      )
    end
  end

  describe 'a client error' do
    it 'leaves the span unmarked, so 4xx does not read as the API failing' do
      get '/nope'

      expect(last_response.status).to eq(404)
      expect(recorded_span_named('GET /nope').status.code)
        .not_to eq(OpenTelemetry::Trace::Status::ERROR)
    end
  end

  describe 'an exception escaping a surface entirely' do
    before { allow(AppSchema).to receive(:execute).and_raise('boom') }

    def post_query
      post '/graphql', JSON.generate(query: '{ notes { nodes { id } } }'), 'CONTENT_TYPE' => 'application/json'
    end

    it 'still answers with the JSON error contract' do
      post_query

      expect(last_response.status).to eq(500)
      expect(JSON.parse(last_response.body)).to eq('errors' => [{ 'message' => 'internal server error' }])
    end

    it 'marks the span failed and records the exception on it' do
      post_query

      span = recorded_span_named('POST /graphql')
      expect(span.status.code).to eq(OpenTelemetry::Trace::Status::ERROR)
      expect(span.events.map(&:name)).to include('exception')
    end
  end
end
