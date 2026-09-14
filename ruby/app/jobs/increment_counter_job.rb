# frozen_string_literal: true
# typed: strict

module Jobs
  # Minimal Resque job to verify the worker can reach Redis: increments a
  # counter key on every run. Enqueue it with `rake resque:test_enqueue`.
  class IncrementCounterJob
    extend T::Sig

    # `Resque.redis` is already namespaced under "resque:" (via redis-namespace),
    # so this ends up stored as the key `resque:test_counter` — no manual prefix.
    KEY = T.let('test_counter', String)

    @queue = T.let(:default, Symbol)

    sig { void }
    def self.perform
      Resque.redis.incr(KEY)
    end
  end
end
