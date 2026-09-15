# frozen_string_literal: true
# typed: false

require 'rack/test'
require_relative '../../../../app/app'

RSpec.describe 'GET /api/v1/notes' do
  include Rack::Test::Methods

  def app
    App.new
  end

  it 'returns all notes as JSON' do
    first = Note.create(note: 'first note')
    second = Note.create(note: 'second note')

    get '/api/v1/notes'
    body = JSON.parse(last_response.body)

    expect(last_response.status).to eq(200)
    expect(body.map { |note| note['id'] }).to contain_exactly(first.id, second.id)
    expect(body.map { |note| note['note'] }).to contain_exactly('first note', 'second note')
  end

  it 'returns an empty array when there are no notes' do
    get '/api/v1/notes'

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to eq([])
  end
end

RSpec.describe 'GET /api/v1/notes/:id' do
  include Rack::Test::Methods

  def app
    App.new
  end

  it 'returns the note' do
    note = Note.create(note: 'remember the milk')

    get "/api/v1/notes/#{note.id}"
    body = JSON.parse(last_response.body)

    expect(last_response.status).to eq(200)
    expect(body['id']).to eq(note.id)
    expect(body['note']).to eq('remember the milk')
  end

  it 'returns 404 with a JSON error body when the note does not exist' do
    get '/api/v1/notes/0'

    expect(last_response.status).to eq(404)
    expect(JSON.parse(last_response.body)['errors']).to include('note not found')
  end
end

RSpec.describe 'POST /api/v1/notes' do
  include Rack::Test::Methods

  def app
    App.new
  end

  it 'persists a note via Services::SaveNote and returns 201 with a Location header' do
    header 'Content-Type', 'application/json'
    post '/api/v1/notes', JSON.generate(note: 'buy milk')
    body = JSON.parse(last_response.body)

    expect(last_response.status).to eq(201)
    expect(last_response.headers['location']).to eq("/api/v1/notes/#{body['id']}")
    expect(body['note']).to eq('buy milk')
    expect(Note[body['id']].note).to eq('buy milk')
  end

  it 'returns 422 with a JSON error body when the note is blank' do
    header 'Content-Type', 'application/json'
    post '/api/v1/notes', JSON.generate(note: '')

    expect(last_response.status).to eq(422)
    expect(JSON.parse(last_response.body)['errors']).to include('note is not present')
  end
end

RSpec.describe 'OPTIONS /api/v1/notes' do
  include Rack::Test::Methods

  def app
    App.new
  end

  it 'returns a CORS preflight response' do
    options '/api/v1/notes'

    expect(last_response.status).to eq(204)
    expect(last_response.headers['access-control-allow-methods']).to eq('GET, POST, PATCH, DELETE, OPTIONS')
  end
end
