module Files
  class Reader
    READ_FUNCTIONS = {
      "csv"     => "read_csv",
      "parquet" => "read_parquet",
      "json"    => "read_json"
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
    end

    def columns
      connection.query("DESCRIBE #{select_all}", path).to_a.map do |name, type, null|
        { name: name, type: postgres_type(type), nullable: null == "YES" }
      end
    end

    def each_batch(size:)
      result = connection.query(select_all, path)
      names = result.columns.map(&:name)

      result.each_slice(size) do |rows|
        yield rows.map { |row| names.zip(row).to_h }
      end
    end

    private

    attr_reader :path, :read_function, :connection

    def select_all
      return "SELECT * FROM read_csv(?, all_varchar = true)" if read_function == "read_csv"

      "SELECT * FROM #{read_function}(?)"
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
      File.foreach(file, mode: "r:BOM|#{encoding}:UTF-8", invalid: :replace, undef: :replace) do |line|
        @utf8_copy.write(line)
      end
      @utf8_copy.close
      @utf8_copy.path
    end

    def postgres_type(duck_type)
      return duck_type.sub("DECIMAL", "numeric") if duck_type.start_with?("DECIMAL")

      TYPES.fetch(duck_type, "text")
    end
  end
end
