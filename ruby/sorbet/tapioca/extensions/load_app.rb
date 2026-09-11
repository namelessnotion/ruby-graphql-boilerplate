# typed: true
# frozen_string_literal: true

# Tapioca requires every file under sorbet/tapioca/extensions/ before loading
# DSL compilers (see Tapioca::Loaders::Dsl#load). Loading the app here — not in
# a compiler — is what makes Sequel::Model subclasses like Note (and their live
# db_schema) available for sorbet/tapioca/compilers/sequel_model.rb to inspect.
require_relative '../../../lib/environment'
