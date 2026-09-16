# frozen_string_literal: true
# typed: false

require 'securerandom'

RSpec.describe RedisConnection, :aggregate_failures do
  let(:key) { "spec:redis_connection:#{SecureRandom.hex(8)}" }

  after { described_class.with { |client| client.call('DEL', key) } }

  it 'points REDIS_URL at the redis configured in .env.test' do
    env_test_url = Dotenv.parse(File.expand_path('../.env.test', __dir__)).fetch('REDIS_URL')

    expect(REDIS_URL).to eq(env_test_url)
  end

  it 'selects the database named in REDIS_URL' do
    expect(described_class.endpoint.database).to eq(URI.parse(REDIS_URL).path.delete_prefix('/').to_i)
  end

  it 'runs commands against a live redis' do
    expect(described_class.with { |client| client.call('PING') }).to eq('PONG')
  end

  it 'returns the block value from with' do
    expect(described_class.with { 42 }).to eq(42)
  end

  it 'round-trips a value' do
    described_class.with do |client|
      client.call('SET', key, 'a value')
    end

    expect(described_class.with { |client| client.call('GET', key) }).to eq('a value')
  end

  it 'reuses a single pooled client across calls' do
    first = described_class.client

    expect(described_class.client).to be(first)
  end

  it 'builds a new client when the process forks, rather than sharing the parent sockets' do
    parent_client = described_class.client
    allow(Process).to receive(:pid).and_return(Process.pid + 1)

    expect(described_class.client).not_to be(parent_client)
  end

  # Falcon runs each request in its own fiber inside one reactor. A blocking
  # client shared between fibers would interleave replies on a single socket;
  # the pool has to hand each fiber its own connection.
  it 'serves concurrent fibers in one reactor' do
    results = Sync do
      tasks = (1..5).map do |index|
        Async { described_class.with { |client| client.call('ECHO', "fiber-#{index}") } }
      end

      tasks.map(&:wait)
    end

    expect(results).to eq((1..5).map { |index| "fiber-#{index}" })
  end

  it 'runs inside an already-running reactor without starting a nested one' do
    expect(Sync { described_class.with { |client| client.call('PING') } }).to eq('PONG')
  end
end
