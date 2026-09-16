# frozen_string_literal: true
# typed: true

require 'dotenv'

APP_ENV = ENV.fetch('APP_ENV', 'development')
Dotenv.load(File.expand_path("../.env.#{APP_ENV}", __dir__))

require 'sequel'
require 'graphql'
require_relative 'core_ext/sorbet_sig'

# The instrumentation gems patch client classes, so both the client and the
# patch have to be in place before the app opens anything. Loading `pg`,
# `redis` and `resque` here costs nothing on its own — none of them connect on
# require — and it is what lets `Observability.configure!` below find them to
# patch. Every connection this file goes on to create is therefore traced.
require 'pg'
require 'redis'
require 'resque'

require_relative 'observability'
Observability.configure!

# for Falcon
Sequel.extension :fiber_concurrency

Sequel::Model.plugin :validation_helpers
Sequel::Model.plugin :timestamps, update_on_create: true

DATABASE_URL = ENV.fetch('DATABASE_URL')

DB = Sequel.connect(DATABASE_URL)

REDIS_URL = ENV.fetch('REDIS_URL')

Resque.redis = REDIS_URL

# Fiber-aware Redis for the request path; see the file for why Resque keeps the
# blocking client above. Requiring it here only defines the module — no
# connection is opened until the first command, which keeps boot fork-safe.
require_relative 'redis_connection'

# Generated protobuf/twirp code (e.g. `require 'holder/v1/holder_pb'`) lives
# under gen/proto rather than lib, so it isn't on the load path by default.
$LOAD_PATH.unshift(File.expand_path('../gen/proto', __dir__))
