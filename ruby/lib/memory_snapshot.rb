# frozen_string_literal: true
# typed: strict

require 'get_process_mem'
require 'sorbet-runtime'

# Reports the current process's RSS, and formats a combined row for the
# memory-footprint history log (see Rakefile's `memory:` namespace, which
# runs each of the 4 memory checks in its own freshly-spawned subprocess —
# bin/memory_rss_boot, bin/memory_rss_request, bin/memory_profile_boot
# --total, bin/memory_profile_request --total — so each number reflects
# that check's own footprint, not the measuring process's).
module MemorySnapshot
  extend T::Sig

  METRICS = T.let(%i[rss_boot_mb rss_request_mb profile_boot_mb profile_request_mb].freeze, T::Array[Symbol])
  CSV_HEADER = T.let((%w[timestamp git_sha ruby_version] + METRICS.map(&:to_s)).freeze, T::Array[String])

  sig { returns(Float) }
  def self.rss_mb
    GetProcessMem.new.mb
  end

  sig { params(metrics: T::Hash[Symbol, Float], git_sha: String, timestamp: Time).returns(T::Array[String]) }
  def self.csv_row(metrics:, git_sha:, timestamp: Time.now.utc)
    [timestamp.iso8601, git_sha, RUBY_VERSION, *METRICS.map { |key| format('%.2f', metrics.fetch(key)) }]
  end
end
