# frozen_string_literal: true
# typed: strict

module Connections
  # Customer connect to fix lookahead eager loading
  class SequelDatasetConnection < GraphQL::Pagination::SequelDatasetConnection
    private

    sig { returns(T::Array[T.untyped]) }
    def load_nodes
      return @nodes if @nodes

      @nodes = T.let(limited_nodes.all, T.nilable(T::Array[T.untyped]))
      T.must(@nodes)
    end
  end
end
