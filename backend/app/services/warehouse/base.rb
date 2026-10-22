module Warehouse
  class Base
    def self.db
      Base.connection
    end

    def self.connection
      @connection ||= Sequel.connect(
        adapter: "postgres",
        host: ENV.fetch("PGHOST"),
        user: ENV.fetch("PGUSER"),
        password: ENV.fetch("PGPASSWORD"),
        database: "makhazen_warehouse_#{Rails.env}"
      )
    end
  end
end
