# frozen_string_literal: true

RSpec.describe HelpScout::SavedReply do
  let(:filters) { nil }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:conn) { Faraday.new { |b| b.adapter(:test, stubs) } }
  let(:client) do
    HelpScout::Client.new(
      client_id: 'client-id',
      client_secret: 'client-secret',
      cache: nil,
      connection: conn
    )
  end

  before do
    allow(Faraday::Connection).to receive(:new).and_return(conn)

    stubs.get('/v2/oauth2/token') do
      [
        200,
        { 'content-type' => 'application/hal+json;charset=UTF-8' },
        ResponseLoader.load_json('auth_token')
      ]
    end
  end

  it 'returns a list of resources' do
    stubs.get("/v2/mailboxes/123456/saved-replies") do
      [
        200,
        { 'content-type' => 'application/hal+json;charset=UTF-8' },
        ResponseLoader.load_json('list_mailbox_saved_replies')
      ]
    end

    outcome = described_class.list(123456)
    expect(outcome).to be_success

    results = outcome.result
    expect(results).to be_an(Array)
  end
end