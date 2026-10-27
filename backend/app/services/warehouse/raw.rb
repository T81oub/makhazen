module Warehouse
  class Raw < Base
    SCHEMA = :raw
    LOADING_SCHEMA = :raw_loading

    def self.create_or_update_table(stream)
      table_name = table(stream)

      key = stream.source_primary_key.map(&:to_sym)
      stream_columns = stream.source_columns

      unless db.table_exists?(table_name)
        db.create_table(table(stream)) do
          stream_columns.each do |source_column|
            column source_column["name"].to_sym, source_column["type"], null: source_column["nullable"]
          end
        end

        db.add_index(table_name, key, unique: true) if key.any?

        return
      end

      db.add_index(table_name, key, unique: true, if_not_exists: true) if key.any?

      existing_columns = db.schema(table_name).map(&:first)

      stream_columns.each do |source_column|
        column_name = source_column["name"].to_sym

        next if existing_columns.include?(column_name)

        db.alter_table(table_name) do
          add_column column_name,
                    source_column["type"],
                    null: source_column["nullable"]
        end
      end
    end

    def self.load(stream, rows)
      key = stream.source_primary_key.map(&:to_sym)
      return db[table(stream)].multi_insert(rows) if key.empty?

      columns = stream.source_columns.map { |c| c["name"].to_sym } - key
      update = columns.to_h { |column| [ column, Sequel[:excluded][column] ] }

      if update.empty?
        db[table(stream)].insert_conflict(target: key).multi_insert(rows)
      else
        db[table(stream)].insert_conflict(target: key, update: update).multi_insert(rows)
      end
    end

    def self.create_loading_table(stream)
      db.create_schema(LOADING_SCHEMA, if_not_exists: true)
      db.drop_table?(loading_table(stream))

      db.create_table(loading_table(stream)) do
        stream.source_columns.each do |source_column|
          column source_column["name"].to_sym, source_column["type"], null: source_column["nullable"]
        end
      end
    end

    def self.load_loading(stream, rows)
      db[loading_table(stream)].multi_insert(rows)
    end

    def self.swap(stream)
      db.transaction do
        db.drop_table?(table(stream))
        db.run("ALTER TABLE #{db.literal(loading_table(stream))} SET SCHEMA #{SCHEMA}")
      end
    end

    def self.drop_loading_table(stream)
      db.drop_table?(loading_table(stream))
    end

    def self.loading_table(stream)
      Sequel[LOADING_SCHEMA][stream.destination_table.to_sym]
    end

    private

    def self.table(stream)
      Sequel[SCHEMA][stream.destination_table.to_sym]
    end
  end
end
