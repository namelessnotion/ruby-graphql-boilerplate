# frozen_string_literal: true
# typed: false

require 'rack/test'
require_relative '../../app/app'

RSpec.describe 'error handling', :aggregate_failures do
  include Rack::Test::Methods

  def app
    App.new
  end

  def json_body
    JSON.parse(last_response.body)
  end

  describe 'an exception raised inside a REST resource route' do
    it 'returns a JSON 500 in the REST error shape instead of a bare 500' do
      allow(Note).to receive(:dataset).and_raise('boom')

      get '/api/v1/notes'

      expect(last_response.status).to eq(500)
      expect(last_response.headers['content-type']).to eq('application/json')
      expect(json_body['errors']).to eq(['internal server error'])
    end
  end

  describe 'an exception raised inside the /api/v1 router' do
    it 'returns a JSON 500 in the REST error shape instead of a bare 500' do
      allow(Api::V1::Notes).to receive(:call).and_raise('boom')

      get '/api/v1/notes'

      expect(last_response.status).to eq(500)
      expect(last_response.headers['content-type']).to eq('application/json')
      expect(json_body['errors']).to eq(['internal server error'])
    end
  end

  describe 'an exception raised inside the /api router' do
    it 'returns a JSON 500 in the REST error shape instead of a bare 500' do
      allow(Api::V1::App).to receive(:call).and_raise('boom')

      get '/api/v1/notes'

      expect(last_response.status).to eq(500)
      expect(last_response.headers['content-type']).to eq('application/json')
      expect(json_body['errors']).to eq(['internal server error'])
    end
  end

  describe 'an exception escaping a surface entirely' do
    it 'is caught by App#call and returned as a JSON 500' do
      allow(AppSchema).to receive(:execute).and_raise('boom')

      header 'Content-Type', 'application/json'
      post '/graphql', JSON.generate(query: '{ notes { nodes { id } } }')

      expect(last_response.status).to eq(500)
      expect(json_body['errors']).to eq([{ 'message' => 'internal server error' }])
    end
  end
end
