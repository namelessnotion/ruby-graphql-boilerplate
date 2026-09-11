# frozen_string_literal: true
# typed: strict

require 'sorbet-runtime'

# include sorbet sig in all classes and modules
class Module
  include T::Sig
end
