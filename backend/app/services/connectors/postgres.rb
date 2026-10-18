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
        db.fetch(<<~'SQL').all
          SELECT n.nspname AS schema, c.relname AS name, c.relkind
          FROM pg_class c
          JOIN pg_namespace n ON c.relnamespace = n.oid
          WHERE NOT c.relispartition
            AND c.relkind IN ('p', 'r')
            AND n.nspname NOT LIKE 'pg\_%'
            AND n.nspname <> 'information_schema'
          ORDER BY schema, name
        SQL
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
