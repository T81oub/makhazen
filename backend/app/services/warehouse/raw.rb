module Warehouse
  class Raw < Base
    SCHEMA = :raw

    def self.create_table(stream)
      db.create_table(table(stream)) do
        stream.source_columns.each do |source_column|
          column source_column["name"].to_sym, source_column["type"], null: source_column["nullable"]
        end
      end
    end

    def self.load(stream, rows)
      db[table(stream)].multi_insert(rows)
    end

    private

    def self.table(stream)
      Sequel[SCHEMA][stream.destination_table.to_sym]
    end
  end
end
