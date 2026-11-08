module LoadingHelpers
  def loaded_rows(columns, schema_name: nil, name: nil)
    stream = Stream.new(schema_name: schema_name, name: name, destination_table: "spec_loading", source_columns: columns.map(&:stringify_keys))
    Warehouse::Raw.create_loading_table(stream)
    yield stream, Sync.new(id: 1, started_at: Time.current)
    Warehouse::Raw.db[Warehouse::Raw.loading_table(stream)].select(*columns.map { |c| c[:name].to_sym }).all.map { |row| row.transform_keys(&:to_s) }
  ensure
    Warehouse::Raw.drop_loading_table(stream)
  end
end

RSpec.configure { |config| config.include LoadingHelpers }
