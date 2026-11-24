# frozen_string_literal: true

module HelpScout
  module Middleware
    # Request middleware for fetching HelpScout credentials.
    class TokenAuth < Faraday::Middleware
      AUTH_HEADER = 'authorization'
      CACHE_KEY = 'helpscout-auth-token'

      # Store tokens for 100m. They expire after 120m.
      EXPIRY = 6_000

      def initialize(app, cache: nil, cache_key: CACHE_KEY, expiry: EXPIRY)
        super(app)
        @cache = cache
        @cache_key = cache_key
        @expiry = expiry
      end

      # @param env [Faraday::Env]
      def call(env)
        # Hack to skip this when we are requesting an auth token.
        return @app.call(env) if env.url.path == HelpScout::AuthToken::PATH

        request_body = env.body
        token, cached = auth_token
        env[:request_headers][AUTH_HEADER] = "Bearer #{token}"
        response = @app.call(env)
        return response unless cached && response.status == 401

        # The cached token was revoked or the credentials changed:
        # drop it, fetch a fresh one and replay the request once.
        @cache.delete(@cache_key)
        env.body = request_body
        env[:request_headers][AUTH_HEADER] = "Bearer #{fetch_auth_token}"
        @app.call(env)
      end

      private

      # @return [Array(String, Boolean)] the token and whether it came from the cache
      def auth_token
        token = @cache&.load(@cache_key)
        return [token, true] if token

        [fetch_auth_token, false]
      end

      def fetch_auth_token
        resp, _opts = HelpScout::AuthToken.create
        outcome = HelpScout::Response.new(resp)

        unless outcome.success?
          raise HelpScout::ClientError, 'Failed to fetch OAuth2 access token'
        end

        outcome.result.access_token.tap do |token|
          @cache.store(@cache_key, token, expires: @expiry) if @cache
        end
      end
    end
  end
end
