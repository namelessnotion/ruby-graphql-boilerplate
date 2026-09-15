# frozen_string_literal: true
# typed: false

require_relative '../../lib/memory_snapshot'

RSpec.describe MemorySnapshot do
  describe '.rss_mb' do
    it 'returns a positive Float' do
      expect(described_class.rss_mb).to be_a(Float).and be > 0
    end
  end

  describe '.csv_row' do
    it 'returns timestamp, git sha, ruby version, and the 4 formatted metrics in METRICS order' do
      timestamp = Time.utc(2026, 1, 1, 12, 0, 0)
      metrics = { rss_boot_mb: 70.0, rss_request_mb: 1.234, profile_boot_mb: 10.806, profile_request_mb: 2.167 }

      row = described_class.csv_row(metrics: metrics, git_sha: 'abc1234', timestamp: timestamp)

      expect(row).to eq(['2026-01-01T12:00:00Z', 'abc1234', RUBY_VERSION, '70.00', '1.23', '10.81', '2.17'])
    end
  end

  describe 'CSV_HEADER' do
    it 'matches timestamp/git_sha/ruby_version plus METRICS' do
      expected = %w[timestamp git_sha ruby_version rss_boot_mb rss_request_mb profile_boot_mb profile_request_mb]

      expect(described_class::CSV_HEADER).to eq(expected)
    end
  end
end
