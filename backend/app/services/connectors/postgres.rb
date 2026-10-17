module Connectors
  class Postgres < Base
    def check
      Sequel.connect(
        adapter: "postgres",
        host: config["host"],
        port: config["port"],
        database: config["database"],
        user: config["username"],
        password: config["password"],
        connect_timeout: 5
      ) { |db| db.test_connection }

      true
    rescue Sequel::DatabaseConnectionError => e
      raise ConnectionError, e.message
    end
  end
end
