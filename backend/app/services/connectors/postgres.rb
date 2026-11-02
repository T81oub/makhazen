module Connectors
  class Postgres < Base
    REQUIRED_CONFIG = [ "host", "port", "database", "username", "password" ].freeze

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
          types = warehouse_types(db, table[:schema], table[:name])

          columns = columns_info.map do |name, info|
            { name: name.to_s, type: types.fetch(name.to_s), nullable: info[:allow_null] }
          end
          primary_key = columns_info.filter_map { |name, info| name.to_s if info[:primary_key] }

          table.merge(columns: columns, primary_key: primary_key)
        end
      end
    end

    def read(stream)
      with_connection do |db|
        data = db[Sequel[stream.schema_name.to_sym][stream.name.to_sym]]

        if stream.updated_at_attr.present? && stream.last_sync.present?
          data = data.where(Sequel[stream.updated_at_attr.to_sym] > stream.last_sync)
        end

        data.paged_each(rows_per_fetch: 1000).each_slice(1000) do |batch|
          yield batch
        end
      end
    end

    private

    def warehouse_types(db, schema, table)
      db.fetch(<<~'SQL', schema, table).to_h { |row| [ row[:name], row[:type] ] }
        SELECT a.attname AS name,
               CASE
                 WHEN tn.nspname = 'pg_catalog' THEN format_type(a.atttypid, a.atttypmod)
                 WHEN t.typtype = 'd' AND bn.nspname = 'pg_catalog' THEN format_type(t.typbasetype, t.typtypmod)
                 ELSE 'text'
               END AS type
        FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace cn ON cn.oid = c.relnamespace
        JOIN pg_type t ON t.oid = a.atttypid
        JOIN pg_namespace tn ON tn.oid = t.typnamespace
        LEFT JOIN pg_type b ON b.oid = t.typbasetype
        LEFT JOIN pg_namespace bn ON bn.oid = b.typnamespace
        WHERE cn.nspname = ? AND c.relname = ?
          AND a.attnum > 0
          AND NOT a.attisdropped
      SQL
    end

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
