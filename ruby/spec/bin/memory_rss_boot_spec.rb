# frozen_string_literal: true
# typed: false

require 'open3'

RSpec.describe 'bin/memory_rss_boot', :aggregate_failures do
  it 'prints a parseable, positive RSS in megabytes' do
    stdout, status = Open3.capture2('bundle', 'exec', 'bin/memory_rss_boot')

    expect(status).to be_success
    expect(Float(stdout.strip)).to be > 0
  end
end
