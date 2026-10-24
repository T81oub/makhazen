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

    def initialize(path, format: File.extname(path).delete(".").downcase)
      @path = path
      @read_function = READ_FUNCTIONS.fetch(format)
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
      "SELECT * FROM #{read_function}(?)"
    end

    def postgres_type(duck_type)
      return duck_type.sub("DECIMAL", "numeric") if duck_type.start_with?("DECIMAL")

      TYPES.fetch(duck_type, "text")
    end
  end
end
