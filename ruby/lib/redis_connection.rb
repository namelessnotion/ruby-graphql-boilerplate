# frozen_string_literal: true
# typed: strict

require 'async'
require 'async/redis'

# Fiber-aware Redis client for the request path.
# Resque workers still use the blocking `redis` gem, as they are
# process-based and so gain nothing from this.
module RedisConnection
  # Upper bound on connections per process. Each one is a socket held open for
  # the process's lifetime, so this caps concurrent commands per Falcon worker
  # rather than describing an expected load.
  POOL_LIMIT = 16

  @client = T.let(nil, T.nilable(Async::Redis::Client))
  @pid = T.let(nil, T.nilable(Integer))

  class << self
    sig { returns(Async::Redis::Endpoint) }
    def endpoint
      @endpoint ||= T.let(Async::Redis::Endpoint.parse(REDIS_URL), T.nilable(Async::Redis::Endpoint))
    end

    sig { returns(Async::Redis::Client) }
    def client
      if @pid != Process.pid
        @client = nil
        @pid = Process.pid
      end

      @client ||= Async::Redis::Client.new(endpoint, limit: POOL_LIMIT)
    end

    sig do
      type_parameters(:Result)
        .params(block: T.proc.params(client: Async::Redis::Client).returns(T.type_parameter(:Result)))
        .returns(T.type_parameter(:Result))
    end
    def with(&block)
      Sync { block.call(client) }
    end
  end
end
