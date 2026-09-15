# frozen_string_literal: true
# typed: false

require 'open3'

RSpec.describe 'bin/memory_rss_request' do
  it 'prints a parseable RSS delta in megabytes' do
    stdout, status = Open3.capture2('bundle', 'exec', 'bin/memory_rss_request')

    expect(status).to be_success
    expect { Float(stdout.strip) }.not_to raise_error
  end
end
