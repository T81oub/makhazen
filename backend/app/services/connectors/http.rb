module Connectors
  class Http < FileBased
    REQUIRED_CONFIG = [ "urls" ].freeze

    def check
      Dir.mktmpdir do |dir|
        locations.each { |location| Files::Fetcher.new(location[:url], into: dir, auth: auth).fetch }
      end
      true
    rescue Files::FetchError => e
      raise ConnectionError, e.message
    end

    private

    def locations
      Array(config["urls"]).map { |url| { id: url, url: url } }
    end

    def auth
      config["auth"]
    end
  end
end
