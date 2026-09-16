# frozen_string_literal: true
# typed: true

require 'dotenv'

APP_ENV = ENV.fetch('APP_ENV', 'development')
Dotenv.load(File.expand_path("../.env.#{APP_ENV}", __dir__))

require 'sequel'
require 'graphql'
require_relative 'core_ext/sorbet_sig'

# for Falcon
Sequel.extension :fiber_concurrency

Sequel::Model.plugin :validation_helpers
Sequel::Model.plugin :timestamps, update_on_create: true

DATABASE_URL = ENV.fetch('DATABASE_URL')

DB = Sequel.connect(DATABASE_URL)

require 'resque'

REDIS_URL = ENV.fetch('REDIS_URL')

Resque.redis = REDIS_URL

# Fiber-aware Redis for the request path; see the file for why Resque keeps the
# blocking client above. Requiring it here only defines the module — no
# connection is opened until the first command, which keeps boot fork-safe.
require_relative 'redis_connection'

# Generated protobuf/twirp code (e.g. `require 'holder/v1/holder_pb'`) lives
# under gen/proto rather than lib, so it isn't on the load path by default.
$LOAD_PATH.unshift(File.expand_path('../gen/proto', __dir__))
