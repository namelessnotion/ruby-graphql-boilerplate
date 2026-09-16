# typed: true
# frozen_string_literal: true

# Add your extra requires here (`bin/tapioca require` can be used to bootstrap this list)
require 'sequel/plugins/state_machine'
# A transitive dependency of the pg instrumentation whose constants tapioca
# does not reach on its own; without this its generated RBI comes out empty.
require 'opentelemetry-helpers-sql-processor'
