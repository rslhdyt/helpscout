# frozen_string_literal: true

RSpec.describe HelpScout do
  it 'has a version number' do
    expect(HelpScout::VERSION).not_to be nil
  end

  it 'has a default base_uri' do
    expect(HelpScout.base_uri).to eq(HelpScout::DEFAULT_BASE_URI)
  end

  it 'can set base_uri' do
    new_uri = 'https://api.some-other-uri.com'
    HelpScout.base_uri = new_uri
    expect(HelpScout.base_uri).to eq(new_uri)
  end

  it 'can set a cache' do
    # Nil by default.
    expect(HelpScout.cache).to be_nil

    HelpScout.cache = HelpScout::Cache::RedisCache
    expect(HelpScout.cache).to be(HelpScout::Cache::RedisCache)
  end

  describe 'credentials' do
    after do
      described_class.client_id = nil
      described_class.client_secret = nil
    end

    it 'keeps credentials per thread' do
      described_class.client_id = 'main-id'
      described_class.client_secret = 'main-secret'

      other = Thread.new do
        described_class.client_id = 'other-id'
        described_class.client_secret = 'other-secret'
        [described_class.client_id, described_class.client_secret]
      end.value

      expect(other).to eq(%w[other-id other-secret])
      expect(described_class.client_id).to eq('main-id')
      expect(described_class.client_secret).to eq('main-secret')
    end

    it 'shares credentials between fibers of the same thread' do
      described_class.client_id = 'main-id'
      expect(Fiber.new { described_class.client_id }.resume).to eq('main-id')
    end
  end

  describe '.new_client' do
    it 'creates a new client' do
      described_class.client_id = 'some_id'
      described_class.client_secret = 'some_secret'
      client = described_class.new_client

      expect(client.base_uri).to eq(described_class.base_uri)
      # expect(client.cache).to eq(described_class.cache)
      expect(client.client_id).to eq(described_class.client_id)
      expect(client.client_secret).to eq(described_class.client_secret)
    end
  end
end
