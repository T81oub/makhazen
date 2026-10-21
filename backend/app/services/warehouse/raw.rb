module Warehouse
  class Raw < Base
    SCHEMA = :raw

    def self.create_table(stream)
      db.create_table(Sequel[SCHEMA][stream.destination_table.to_sym]) do
        stream.source_columns.each do |source_column|
          column source_column["name"].to_sym, source_column["type"], null: source_column["nullable"]
        end
      end
    end

    def self.load(stream, rows)
    end
  end
end
