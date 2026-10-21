module Connectors
  class Postgres < Base
    def check
      with_connection { |db| db.test_connection }

      true
    rescue Sequel::DatabaseConnectionError => e
      raise ConnectionError, e.message
    end

    def discover
      with_connection do |db|
        tables = db.fetch(<<~'SQL').all
          SELECT n.nspname AS schema, c.relname AS name, c.relkind
          FROM pg_class c
          JOIN pg_namespace n ON c.relnamespace = n.oid
          WHERE NOT c.relispartition
            AND c.relkind IN ('p', 'r')
            AND n.nspname NOT LIKE 'pg\_%'
            AND n.nspname <> 'information_schema'
          ORDER BY schema, name
        SQL

        tables.map do |table|
          columns_info = db.schema(Sequel.qualify(*table.values_at(:schema, :name)))

          columns = columns_info.map do |name, info|
            { name: name.to_s, type: info[:db_type], nullable: info[:allow_null] }
          end
          primary_key = columns_info.filter_map { |name, info| name.to_s if info[:primary_key] }

          table.merge(columns: columns, primary_key: primary_key)
        end
      end
    end

    def read(stream)
      with_connection do |db|
        db[Sequel[stream.schema_name.to_sym][stream.name.to_sym]].paged_each(rows_per_fetch: 1000).each_slice(1000) do |batch|
          yield batch
        end
      end
    end

    private

    def with_connection
      Sequel.connect(
        adapter: "postgres",
        host: config["host"],
        port: config["port"],
        database: config["database"],
        user: config["username"],
        password: config["password"],
        connect_timeout: 5
      ) { |db| yield db }
    rescue Sequel::DatabaseConnectionError => e
      raise ConnectionError, e.message
    end
  end
end
