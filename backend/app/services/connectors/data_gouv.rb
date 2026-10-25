module Connectors
  # Every data file of a data.gouv.fr dataset.
  class DataGouv < FileBased
    API = "https://www.data.gouv.fr/api/1/".freeze
    REQUIRED_CONFIG = [ "dataset" ].freeze

    def check
      dataset
      true
    end

    private

    # "latest" always redirects to the current file, even if the producer moves it.
    def locations
      data_resources.map { |resource| { id: resource["id"], url: resource["latest"] } }
    end

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
  end
end
