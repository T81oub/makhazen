module Files
  class Unpacker
    ZIP  = "PK".b
    GZIP = "\x1F\x8B".b

    def initialize(path, into:)
      @path = path
      @into = into
    end

    def files
      case File.binread(path, 2)
      when ZIP  then unzip
      when GZIP then [ gunzip ]
      else [ path ]
      end
    end

    private

    attr_reader :path, :into

    def unzip
      Zip::File.open(path) do |zip|
        zip.entries.select { |entry| entry.file? && data_file?(entry.name) }.map do |entry|
          name = File.basename(entry.name)
          entry.extract(name, destination_directory: into)
          File.join(into, name)
        end
      end
    end

    def gunzip
      target = File.join(into, File.basename(path, ".gz"))
      Zlib::GzipReader.open(path) do |gz|
        File.open(target, "wb") { |out| IO.copy_stream(gz, out) }
      end
      target
    end

    def data_file?(name)
      Reader::READ_FUNCTIONS.key?(File.extname(name).delete(".").downcase)
    end
  end
end
