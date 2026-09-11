# frozen_string_literal: true
# typed: false

require 'uri'

RSpec.describe 'database connection', :aggregate_failures do
  let(:expected_database) { URI.parse(DATABASE_URL).path.delete_prefix('/') }

  it 'boots with the test environment' do
    expect(APP_ENV).to eq('test')
  end

  it 'points DATABASE_URL at the database configured in .env.test' do
    env_test_url = Dotenv.parse(File.expand_path('../.env.test', __dir__)).fetch('DATABASE_URL')

    expect(DATABASE_URL).to eq(env_test_url)
  end

  it 'establishes a live connection to the test database' do
    expect(DB.test_connection).to be(true)
  end

  it 'is connected to the database named in DATABASE_URL' do
    expect(DB.opts[:database]).to eq(expected_database)
  end

  it 'has run the notes migration against the test database' do
    expect(DB.table_exists?(:notes)).to be(true)
  end
end
