# frozen_string_literal: true
# typed: strict

require 'state_machines/sequel'

require_relative '../types/query_type'
require_relative '../types/mutation_type'
require_relative '../connections/sequel_dataset_connection'

# GraphQL schema for the MoneyFlow application
class AppSchema < GraphQL::Schema
  query Types::QueryType
  mutation Types::MutationType

  max_complexity 300
  max_depth 15

  connections.add(Sequel::Dataset, Connections::SequelDatasetConnection)

  # Persistence-layer exceptions are translated to client-facing GraphQL
  # errors once, here, so resolvers stay thin and every mutation reports the
  # same failure the same way.
  rescue_from(Sequel::NoMatchingRow) { raise GraphQL::ExecutionError, 'note not found' }
  rescue_from(Sequel::ValidationFailed) { |error| raise GraphQL::ExecutionError, error.message }
  rescue_from(StateMachines::Sequel::FailedTransition) { |error| raise GraphQL::ExecutionError, error.message }
end
