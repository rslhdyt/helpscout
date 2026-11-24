# frozen_string_literal: true

require 'uri'
require 'pry'

RSpec.describe HelpScout::Middleware::TokenAuth do
  def auth_header(env)
    env[:request_headers]['authorization']
  end

  def request
    env = {
      url: URI('http://example.com'),
      request_headers: Faraday::Utils::Headers.new
    }
    app = make_app
    app.call(Faraday::Env.from(env))
  end

  def make_app
    described_class.new(->(env) { env }, **options)
  end

  describe '#call' do
    let(:options) { {} }
    let(:response) { double('Response') }
    let(:body) { ResponseLoader.load_json('auth_token') }
    let(:success) { true }
    let(:status) { 200 }

    before do
      allow(HelpScout::AuthToken).to receive(:create)
        .and_return([response, {}])
      allow(response).to receive(:success?).and_return(success)
      allow(response).to receive(:body).and_return(body)
      allow(response).to receive(:status).and_return(status)
    end

    context 'without cache' do
      it 'adds an authorization token' do
        token = "Bearer #{JSON.parse(body, symbolize_names: true)[:access_token]}"
        expect(auth_header(request)).to eq(token)
      end

      context 'on failure' do
        let(:success) { false }
        let(:status) { 401 }

        it 'raises an error' do
          expect { request }.to raise_exception(HelpScout::ClientError)
        end
      end
    end

    context 'with cache' do
      let(:expiry) { 60 }
      let(:cache) do
        Moneta.build do
          use :Expires
          adapter :Memory
        end
      end
      let(:options) { { cache: cache, expiry: expiry } }
      let(:token) { 'this-is-an-auth-token' }

      context 'cache hit' do
        it 'returns cached value' do
          expect(HelpScout::AuthToken).not_to receive(:create)
          cache.store(described_class::CACHE_KEY, token, expires: expiry)

          expect(auth_header(request)).to eq("Bearer #{token}")
        end

        it 'fetches new auth token when expired' do
          fetched_token = "Bearer #{JSON.parse(body, symbolize_names: true)[:access_token]}"
          cache.store(described_class::CACHE_KEY, token, expires: 1)
          sleep(1)

          expect(auth_header(request)).to eq(fetched_token)
        end
      end

      context 'cache miss' do
        it 'fetches new auth token' do
          fetched_token = "Bearer #{JSON.parse(body, symbolize_names: true)[:access_token]}"
          expect(auth_header(request)).to eq(fetched_token)
        end

        it 'fetches one token for several requests' do
          expect(HelpScout::AuthToken).to receive(:create).once
          3.times { request }
        end

        context 'with a short expiry' do
          let(:expiry) { 1 }

          it 'stores the token with the expiry' do
            request
            expect(cache.key?(described_class::CACHE_KEY)).to be(true)
            sleep(1.1)
            expect(cache.key?(described_class::CACHE_KEY)).to be(false)
          end
        end
      end

      context 'with a cache key' do
        let(:options) { { cache: cache, cache_key: 'helpscout-auth-token:abc' } }

        it 'reads and writes only that key' do
          cache.store(described_class::CACHE_KEY, token)
          request
          expect(cache.load('helpscout-auth-token:abc')).not_to eq(token)
          expect(cache.load('helpscout-auth-token:abc')).not_to be_nil
        end
      end

      context 'when the cached token is rejected' do
        let(:fresh_token) { JSON.parse(body, symbolize_names: true)[:access_token] }

        def make_app
          statuses = @statuses
          seen = @seen = []
          app = lambda do |env|
            seen << [env[:request_headers]['authorization'], env.body]
            env.status = statuses.shift
            env.body = 'response body'
            env
          end
          described_class.new(app, **options)
        end

        def post_request
          env = {
            method: :post,
            url: URI('http://example.com/v2/conversations'),
            body: '{"a":1}',
            request_headers: Faraday::Utils::Headers.new
          }
          make_app.call(Faraday::Env.from(env))
        end

        before { cache.store(described_class::CACHE_KEY, token) }

        it 'fetches a new token and replays the request once' do
          @statuses = [401, 200]
          result = post_request

          expect(result.status).to eq(200)
          expect(@seen).to eq([["Bearer #{token}", '{"a":1}'], ["Bearer #{fresh_token}", '{"a":1}']])
          expect(cache.load(described_class::CACHE_KEY)).to eq(fresh_token)
        end

        it 'returns a second 401 as is' do
          @statuses = [401, 401]
          expect(post_request.status).to eq(401)
          expect(@seen.size).to eq(2)
        end

        it 'does not replay a 401 when the token was just fetched' do
          cache.delete(described_class::CACHE_KEY)
          @statuses = [401]
          expect(post_request.status).to eq(401)
          expect(@seen.size).to eq(1)
        end
      end
    end
  end
end
