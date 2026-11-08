module Files
  class Reader
    READ_FUNCTIONS = {
      "csv"     => "read_csv",
      "parquet" => "read_parquet",
      "json"    => "read_json",
      "xlsx"    => "read_xlsx"
    }.freeze

    # DuckDB type => Postgres type. Anything else is stored as text.
    TYPES = {
      "BOOLEAN"   => "boolean",
      "TINYINT"   => "smallint",
      "SMALLINT"  => "smallint",
      "INTEGER"   => "integer",
      "BIGINT"    => "bigint",
      "HUGEINT"   => "numeric",
      "UTINYINT"  => "smallint",
      "USMALLINT" => "integer",
      "UINTEGER"  => "bigint",
      "UBIGINT"   => "numeric",
      "FLOAT"     => "real",
      "DOUBLE"    => "double precision",
      "DATE"      => "date",
      "TIME"      => "time",
      "TIMESTAMP" => "timestamp",
      "TIMESTAMP WITH TIME ZONE" => "timestamptz",
      "INTERVAL"  => "interval",
      "UUID"      => "uuid",
      "BLOB"      => "bytea",
      "VARCHAR"   => "text"
    }.freeze

    def initialize(path, format: File.extname(path).delete(".").downcase, encoding: nil)
      @read_function = READ_FUNCTIONS.fetch(format)
      @path = read_function == "read_csv" ? to_utf8(path, encoding || detect_encoding(path)) : path
      @connection = DuckDB::Database.open.connect
      %w[INSTALL LOAD].each { |verb| connection.query("#{verb} excel") } if read_function == "read_xlsx"
    end

    def columns
      @columns ||= described.zip(clean_names).map do |(_, type, null), name|
        { name: name, type: postgres_type(type), nullable: null == "YES" }
      end
    end

    def load_into(stream, sync)
      attach_warehouse
      connection.query(
        "INSERT INTO wh.raw_loading.\"#{stream.destination_table}\" SELECT #{select_list}, ?::TIMESTAMPTZ, ?::BIGINT FROM #{source}",
        sync.started_at.utc.iso8601(6), sync.id, path
      ).rows_changed
    end

    private

    attr_reader :path, :read_function, :connection

    def attach_warehouse
      opts = Warehouse::Raw.db.opts
      %w[INSTALL LOAD].each { |verb| connection.query("#{verb} postgres") }
      connection.query("ATTACH 'host=#{opts[:host]} dbname=#{opts[:database]} user=#{opts[:user]} password=#{opts[:password]}' AS wh (TYPE postgres)")
    end

    def source
      return "#{read_function}(?, all_varchar = true)" if %w[read_csv read_xlsx].include?(read_function)

      "#{read_function}(?)"
    end

    def select_list
      described.zip(columns).map do |(original, *), column|
        quoted = "\"#{original.gsub('"', '""')}\""
        value = column[:type] == "jsonb" ? "to_json(#{quoted})" : quoted
        "#{value} AS \"#{column[:name]}\""
      end.join(", ")
    end

    def described
      @described ||= connection.query("DESCRIBE SELECT * FROM #{source}", path).to_a
    end

    def clean_names
      described.each_with_object([]) do |(original, *), names|
        base = ActiveSupport::Inflector.transliterate(original).downcase.gsub(/[^a-z0-9]+/, "_").delete_prefix("_").delete_suffix("_")
        base = "col_#{base}".chomp("_") unless base.match?(/\A[a-z]/)
        base = base[0, 59]
        name = base
        suffix = 1
        name = "#{base}_#{suffix += 1}" while names.include?(name)
        names << name
      end
    end

    def detect_encoding(file)
      head = File.binread(file, 2).to_s
      return "UTF-16LE" if head == "\xFF\xFE".b
      return "UTF-16BE" if head == "\xFE\xFF".b
      return "UTF-8" if utf8?(file)

      "Windows-1252"
    end

    def utf8?(file)
      File.foreach(file, mode: "rb") do |line|
        return false unless line.force_encoding(Encoding::UTF_8).valid_encoding?
      end
      true
    end

    def to_utf8(file, encoding)
      return file if Encoding.find(encoding) == Encoding::UTF_8

      @utf8_copy = Tempfile.new([ "utf8", ".csv" ])
      mode = encoding.start_with?("UTF") ? "r:BOM|#{encoding}:UTF-8" : "r:#{encoding}:UTF-8"
      File.foreach(file, mode: mode, invalid: :replace, undef: :replace) do |line|
        @utf8_copy.write(line)
      end
      @utf8_copy.close
      @utf8_copy.path
    end

    def postgres_type(duck_type)
      return duck_type.sub("DECIMAL", "numeric") if duck_type.start_with?("DECIMAL")
      return "jsonb" if duck_type.start_with?("STRUCT", "MAP", "UNION", "JSON") || duck_type.end_with?("]")

      TYPES.fetch(duck_type, "text")
    end
  end
end
