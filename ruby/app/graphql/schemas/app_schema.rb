# frozen_string_literal: true
# typed: strict

require 'state_machines/sequel'

require_relative '../types/query_type'
require_relative '../types/mutation_type'
require_relative '../connections/sequel_dataset_connection'

# GraphQL schema for App
class AppSchema < GraphQL::Schema
  query Types::QueryType
  mutation Types::MutationType

  max_complexity 300
  max_depth 15

  connections.add(Sequel::Dataset, Connections::SequelDatasetConnection)

  # Persistence-layer exceptions are translated to client-facing GraphQL
  # errors once, here, so resolvers stay thin and every mutation reports the
  # same failure the same way.
  #
  # Each one is also recorded on the span in scope before it is translated —
  # this is the only place the original exception still exists, since what the
  # client receives is a message with no class, backtrace or cause. See
  # Observability.record_exception for why these do not mark the span failed.
  rescue_from(Sequel::NoMatchingRow) do |error|
    Observability.record_exception(error)
    raise GraphQL::ExecutionError, "#{resource_name(error)} not found"
  end

  rescue_from(Sequel::ValidationFailed) do |error|
    Observability.record_exception(error)
    raise GraphQL::ExecutionError, error.message
  end

  rescue_from(StateMachines::Sequel::FailedTransition) do |error|
    Observability.record_exception(error)
    raise GraphQL::ExecutionError, error.message
  end

  # `Model.with_pk!` is a dataset method delegated onto the class
  # (`Plugins.def_dataset_methods`), so it raises with `dataset` set to the
  # *dataset instance*, not the model class — `dataset.model` is what gives
  # back e.g. `Note` for `Note.with_pk!`. A dataset with no associated model
  # falls back to a generic label rather than raising `NoMethodError` out of
  # an error handler.
  sig { params(error: Sequel::NoMatchingRow).returns(String) }
  def self.resource_name(error)
    dataset = error.dataset
    return 'record' unless dataset.respond_to?(:model) && dataset.model.respond_to?(:name)

    dataset.model.name.to_s.split('::').last.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
  end
  private_class_method :resource_name
end
