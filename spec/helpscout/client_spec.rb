# frozen_string_literal: true

RSpec.describe HelpScout::Client do
  let(:client_id) { 'some-client-id' }
  let(:client_secret) { 'some-client-secret' }
  let(:cache) { nil }

  describe '#initialize' do
    it 'creates a new client with connection' do
      expect(Faraday::Connection).to receive(:new)
        .with(HelpScout::DEFAULT_BASE_URI, headers: described_class::DEFAULT_HEADERS)

      client = described_class.new(
        client_id: client_id,
        client_secret: client_secret,
        cache: cache
      )

      expect(client.client_id).to eq(client_id)
      expect(client.client_secret).to eq(client_secret)
      expect(client.cache).to eq(cache)
    end

    it 'throws an error when missing required options' do
      expect {
        described_class.new
      }.to raise_exception(ArgumentError)
    end
  end

  describe 'token cache' do
    def token_middleware(client)
      conn = client.instance_variable_get(:@connection)
      handler = conn.builder.handlers.find { |h| h.klass == HelpScout::Middleware::TokenAuth }
      handler.build(->(env) { env })
    end

    def client_for(id, secret, cache: nil)
      described_class.new(client_id: id, client_secret: secret, cache: cache)
    end

    it 'uses the process token store when no cache is set' do
      mw = token_middleware(client_for('a', 'b'))
      expect(mw.instance_variable_get(:@cache)).to be(HelpScout.token_store)
    end

    it 'uses the configured cache when set' do
      cache = Moneta.new(:Memory, expires: true)
      mw = token_middleware(client_for('a', 'b', cache: cache))
      expect(mw.instance_variable_get(:@cache)).to be(cache)
    end

    it 'keys tokens by credentials without exposing the secret' do
      key = ->(id, secret) { token_middleware(client_for(id, secret)).instance_variable_get(:@cache_key) }

      expect(key.call('a', 'b')).to eq(key.call('a', 'b'))
      expect(key.call('a', 'b')).not_to eq(key.call('a', 'c'))
      expect(key.call('a', 'b')).not_to eq(key.call('x', 'b'))
      expect(key.call('a:b', 'c')).not_to eq(key.call('a', 'b:c'))
      expect(key.call('a', 'secret-value')).not_to include('secret-value')
    end
  end

  describe '#execute_request' do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:conn) { Faraday.new { |b| b.adapter(:test, stubs) } }

    let(:client) do
      described_class.new(
        client_id: client_id,
        client_secret: client_secret,
        cache: cache,
        connection: conn
      )
    end

    before { allow(Faraday).to receive(:new).and_return(conn) }

    # This is slow. Consider unrolling.
    %i[get post put patch delete].each do |method|
      it "sends a #{method.to_s.upcase} request" do
        stubs.send(method, '/v2/items') do |env|
          expect(env.method).to eq(method)
          expect(env.url.path).to eq('/v2/items')
          expect(env.params).to eq({})
          [
            200,
            { 'Content-Type' => 'application/json' },
            JSON.generate(hello: 'world')
          ]
        end

        client.execute_request(method, '/v2/items')
      end
    end
  end
end
