module Connectors
  class DataGouv < Base
    API = "https://www.data.gouv.fr/api/1/".freeze
    REQUIRED_CONFIG = [ "dataset" ].freeze

    def check
      dataset
      true
    end

    def discover
      data_resources.flat_map do |resource|
        Dir.mktmpdir do |dir|
          files_of(resource, dir).map do |path|
            name = stream_name(path)
            {
              schema: resource["id"],
              name: name,
              destination: name,
              columns: Files::Reader.new(path).columns,
              primary_key: []
            }
          end
        end
      rescue Files::FetchError => e
        Rails.logger.warn("Skipping resource #{resource['id']}: #{e.message}")
        []
      end
    end

    def read(stream)
      resource = data_resources.find { |r| r["id"] == stream.schema_name }
      raise ConnectionError, "resource #{stream.schema_name} is gone from the dataset" unless resource

      Dir.mktmpdir do |dir|
        path = files_of(resource, dir).find { |file| stream_name(file) == stream.name }
        raise ConnectionError, "#{stream.name} is no longer in resource #{stream.schema_name}" unless path

        Files::Reader.new(path).each_batch(size: 1000) { |batch| yield batch }
      end
    end

    private

    def dataset
      @dataset ||= api.get("datasets/#{config['dataset']}/").body
    rescue Faraday::ResourceNotFound
      raise ConnectionError, "dataset #{config['dataset']} not found on data.gouv.fr"
    rescue Faraday::Error => e
      raise ConnectionError, e.message
    end

    def api
      Faraday.new(url: API) do |f|
        f.response :raise_error
        f.request :retry, max: 3, retry_statuses: [ 429, 500, 502, 503, 504 ]
        f.response :json
      end
    end

    def data_resources
      dataset["resources"].select { |resource| resource["type"] == "main" }
    end

    def files_of(resource, dir)
      download = Files::Fetcher.new(resource["latest"], into: dir).fetch
      Files::Unpacker.new(download.path, into: dir).files
    end

    def stream_name(path)
      File.basename(path, ".*").downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    end
  end
end
