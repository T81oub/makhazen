module Files
  class Fetcher
    Download = Data.define(:path, :sha256)

    RETRY = { max: 3, interval: 0.5, backoff_factor: 2, retry_statuses: [ 429, 500, 502, 503, 504 ] }.freeze

    def initialize(url, into:, auth: nil)
      @url = url
      @into = into
      @auth = auth
    end

    def fetch
      path = File.join(into, file_name)

      response = File.open(path, "wb") do |file|
        connection(file).get(url) do |request|
          request.options.on_data = proc do |chunk, _size, env|
            # Redirects and errors have a body too: only keep the real file.
            file.write(chunk) if env.status.between?(200, 299)
          end
        end
      end

      final_path = File.join(into, file_name(response.env.url.to_s))
      File.rename(path, final_path)

      Download.new(path: final_path, sha256: Digest::SHA256.file(final_path).hexdigest)
    rescue Faraday::Error => e
      raise FetchError, "#{url}: #{e.message}"
    end

    private

    attr_reader :url, :into, :auth

    def connection(file)
      Faraday.new do |f|
        # Outermost: raise only once the retries are used up.
        f.response :raise_error
        # A retry starts the download again, so empty the file first.
        f.request :retry, **RETRY, retry_block: proc { file.rewind; file.truncate(0) }
        authenticate(f)
        f.response :follow_redirects
      end
    end

    def authenticate(f)
      case auth&.fetch("type")
      when nil      then nil
      when "header" then f.headers[auth.fetch("name")] = auth.fetch("value")
      when "bearer" then f.request :authorization, "Bearer", auth.fetch("token")
      when "basic"  then f.request :authorization, :basic, auth.fetch("username"), auth.fetch("password")
      else raise ArgumentError, "unknown auth type: #{auth['type']}"
      end
    end

    def file_name(from = url)
      name = File.basename(URI(from).path)
      name.match?(/\A\w[\w.-]*\z/) ? name : "download"
    end
  end
end
