# frozen_string_literal: true
# typed: strict

require 'json'
require 'sorbet-runtime'

# The representative GraphQL + REST workload shared by bin/memory_profile_request
# and bin/memory_rss_request, kept in one place so the two never drift apart.
# Run inside a rolled-back transaction so neither leaves persisted rows behind,
# regardless of which database APP_ENV points at.
module MemoryWorkload
  extend T::Sig

  MUTATION = T.let('mutation($note: String!) { saveNote(note: $note) { note { id } } }', String)
  QUERY = T.let('{ notes { edges { node { id } } } }', String)
  JSON_HEADERS = T.let({ 'CONTENT_TYPE' => 'application/json' }.freeze, T::Hash[String, String])

  sig { params(request: Rack::MockRequest).void }
  def self.run(request)
    DB.transaction(rollback: :always) do
      request.post('/graphql', input: JSON.generate(query: MUTATION, variables: { note: 'profiled note' }))
      request.post('/graphql', input: JSON.generate(query: QUERY))
      request.post('/api/v1/notes', input: JSON.generate(note: 'profiled rest note'), **JSON_HEADERS)
      request.get('/api/v1/notes')
    end
  end
end
