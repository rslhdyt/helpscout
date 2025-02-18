# frozen_string_literal: true

module HelpScout
  class SavedReply < HelpScout::Resource
    include HelpScout::API::List

    OBJECT_NAME = 'saved-reply'

    # Override because the endpoint is nested under mailboxes
    def self.resource_url
      '/v2/mailboxes'
    end

    # Override to handle the nested structure
    def self.list(mailbox_id, params = {}, opts = {})
      url = "#{resource_url}/#{mailbox_id}/saved-replies"
      r, _opts = request(:get, url, params, opts)

      Struct.new(:success?, :result).new(r.status == 200, JSON.parse(r.body))
    rescue JSON::ParserError
      Struct.new(:success?, :result).new(false, {})
    end
  end
end