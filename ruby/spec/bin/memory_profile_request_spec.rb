# frozen_string_literal: true
# typed: false

require 'open3'

RSpec.describe 'bin/memory_profile_request' do
  it 'prints a request-cycle allocation report' do
    stdout, status = Open3.capture2('bundle', 'exec', 'bin/memory_profile_request')

    expect(status).to be_success
    expect(stdout).to match(/allocated/i)
  end

  it 'prints just the total allocated MB with --total' do
    stdout, status = Open3.capture2('bundle', 'exec', 'bin/memory_profile_request', '--total')

    expect(status).to be_success
    expect(Float(stdout.strip)).to be > 0
  end
end
