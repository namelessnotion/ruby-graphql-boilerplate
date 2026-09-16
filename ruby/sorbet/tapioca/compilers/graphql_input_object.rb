# typed: strict
# frozen_string_literal: true

# The app is loaded by sorbet/tapioca/extensions/load_app.rb — see that file
# for why this can't happen here.
return unless defined?(GraphQL::Schema::InputObject)

module Tapioca
  module Compilers
    # Generates typed reader methods for `GraphQL::Schema::InputObject` subclasses,
    # based on their declared `argument`s. Sorbet has no static visibility into
    # arguments added via the `argument` class macro otherwise, so calling a
    # generated reader (e.g. `input.due_at`) from application code is an error
    # under `typed: strict` without this.
    class GraphqlInputObject < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: T.class_of(::GraphQL::Schema::InputObject) } }

      # GraphQL-Ruby's built-in scalar names — see `Sequel::Model#schema_column_type`
      # for the equivalent table on the Sequel side (`sequel_model.rb`, `RUBY_TYPES`).
      # Anything absent (a custom Object/Enum/InputObject argument type) falls back
      # to `T.untyped`.
      RUBY_TYPES = T.let(
        {
          'String' => 'String',
          'Int' => 'Integer',
          'Float' => 'Float',
          'Boolean' => 'T::Boolean',
          'ID' => 'String',
          'ISO8601DateTime' => 'Time'
        }.freeze,
        T::Hash[String, String]
      )

      class << self
        extend T::Sig

        sig { override.returns(T::Enumerable[T::Module[T.anything]]) }
        def gather_constants
          descendants_of(::GraphQL::Schema::InputObject)
        end
      end

      sig { override.void }
      def decorate
        arguments = T.unsafe(constant).arguments.values
        return if arguments.empty?

        root.create_path(constant) do |klass|
          klass.create_module('GeneratedArgumentMethods') { |mod| add_arguments(mod, arguments) }
          klass.create_include('GeneratedArgumentMethods')
        end
      end

      private

      sig { params(mod: RBI::Scope, arguments: T::Array[T.untyped]).void }
      def add_arguments(mod, arguments)
        arguments.each do |argument|
          mod.create_method(argument.keyword.to_s, return_type: type_for(argument))
        end
      end

      sig { params(argument: T.untyped).returns(String) }
      def type_for(argument)
        type = RUBY_TYPES.fetch(argument.type.unwrap.graphql_name, 'T.untyped')
        return type if type == 'T.untyped'

        argument.type.non_null? ? type : "T.nilable(#{type})"
      end
    end
  end
end
