module Warehouse
  class Raw < Base
    SCHEMA = "raw".freeze

    def self.create_table(stream)
    end

    def self.load(stream, rows)
    end
  end
end
