# frozen_string_literal: true
# typed: strict

require_relative 'boot'

# Eager-loads every application file.
module Environment
  extend T::Sig

  ROOT = T.let(File.expand_path('..', __dir__), String)

  # Ordering is cosmetic — every file require_relatives its own dependencies — but
  # keeping models ahead of their consumers matches how the app is layered.
  LAYERS = T.let(%w[types models services graphql].freeze, T::Array[String])

  sig { void }
  def self.load_app!
    LAYERS.each do |layer|
      Dir[File.join(ROOT, 'app', layer, '**', '*.rb')].each { |file| require file }
    end
  end
end

Environment.load_app!
