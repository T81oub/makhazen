module Connectors
  # Shared by connectors that download files (data.gouv, any URL).
  # A child only says where the files are, with #locations:
  #   [{ id: "...", url: "..." }]
  # The id becomes the stream's schema, so it must stay the same between syncs.
  class FileBased < Base
    BATCH_SIZE = 1000

    def discover
      locations.flat_map do |location|
        Dir.mktmpdir do |dir|
          files_of(location, dir).map do |path|
            name = stream_name(path)
            {
              schema: location[:id],
              name: name,
              destination: name,
              columns: Files::Reader.new(path).columns,
              primary_key: []
            }
          end
        end
      rescue Files::FetchError => e
        Rails.logger.warn("Skipping #{location[:id]}: #{e.message}")
        []
      end
    end

    def read(stream)
      location = locations.find { |l| l[:id] == stream.schema_name }
      raise ConnectionError, "#{stream.schema_name} is gone from the source" unless location

      Dir.mktmpdir do |dir|
        path = files_of(location, dir).find { |file| stream_name(file) == stream.name }
        raise ConnectionError, "#{stream.name} is no longer in #{stream.schema_name}" unless path

        Files::Reader.new(path).each_batch(size: BATCH_SIZE) { |batch| yield batch }
      end
    end

    private

    def locations
      raise NotImplementedError, "#{self.class.name} must implement #locations"
    end

    # Credentials for the downloads. Children override it when they have some.
    def auth
      nil
    end

    # Downloads a location and gives the data files inside it.
    def files_of(location, dir)
      download = Files::Fetcher.new(location[:url], into: dir, auth: auth).fetch
      Files::Unpacker.new(download.path, into: dir).files
    end

    # "DS_DECHET_SERVICES_data.csv" => "ds_dechet_services_data"
    def stream_name(path)
      File.basename(path, ".*").downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    end
  end
end
