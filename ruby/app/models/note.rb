# frozen_string_literal: true
# typed: strict

# Model of persisted notes
class Note < Sequel::Model
  extend T::Sig

  sig { void }
  def validate
    super
    validates_presence [:note]
  end
end
