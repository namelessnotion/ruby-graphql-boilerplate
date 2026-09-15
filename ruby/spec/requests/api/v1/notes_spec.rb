# frozen_string_literal: true
# typed: false

require 'rack/test'
require_relative '../../../../app/app'

RSpec.describe '/api/v1/notes', :aggregate_failures do
  include Rack::Test::Methods

  def app
    App.new
  end

  def json_body
    JSON.parse(last_response.body)
  end

  describe 'GET /api/v1/notes' do
    it 'returns all notes as JSON' do
      first = Note.create(note: 'first note')
      second = Note.create(note: 'second note')

      get '/api/v1/notes'

      expect(last_response.status).to eq(200)
      expect(json_body.map { |note| note['id'] }).to contain_exactly(first.id, second.id)
      expect(json_body.map { |note| note['note'] }).to contain_exactly('first note', 'second note')
    end

    it 'returns an empty array when there are no notes' do
      get '/api/v1/notes'

      expect(last_response.status).to eq(200)
      expect(json_body).to eq([])
    end
  end

  describe 'GET /api/v1/notes/:id' do
    it 'returns the note' do
      note = Note.create(note: 'remember the milk')

      get "/api/v1/notes/#{note.id}"

      expect(last_response.status).to eq(200)
      expect(json_body['id']).to eq(note.id)
      expect(json_body['note']).to eq('remember the milk')
    end

    it 'returns 404 with a JSON error body when the note does not exist' do
      get '/api/v1/notes/0'

      expect(last_response.status).to eq(404)
      expect(json_body['errors']).to include('note not found')
    end
  end

  describe 'POST /api/v1/notes' do
    it 'persists a note via Services::SaveNote and returns 201 with a Location header' do
      header 'Content-Type', 'application/json'
      post '/api/v1/notes', JSON.generate(note: 'buy milk')

      expect(last_response.status).to eq(201)
      expect(last_response.headers['location']).to eq("/api/v1/notes/#{json_body['id']}")
      expect(json_body['note']).to eq('buy milk')
      expect(Note[json_body['id']].note).to eq('buy milk')
    end

    it 'returns 422 with a JSON error body when the note is blank' do
      header 'Content-Type', 'application/json'
      post '/api/v1/notes', JSON.generate(note: '')

      expect(last_response.status).to eq(422)
      expect(json_body['errors']).to include('note is not present')
    end
  end

  describe 'OPTIONS /api/v1/notes' do
    it 'returns a CORS preflight response' do
      options '/api/v1/notes'

      expect(last_response.status).to eq(204)
      expect(last_response.headers['access-control-allow-methods']).to eq('GET, POST, PATCH, DELETE, OPTIONS')
    end
  end
end
