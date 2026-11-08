module LoadingHelpers
  def loaded_rows(columns, schema_name: nil, name: nil)
    stream = Stream.new(schema_name: schema_name, name: name, destination_table: "spec_loading", source_columns: columns.map(&:stringify_keys))
    Warehouse::Raw.create_loading_table(stream)
    yield stream, Sync.new(id: 1, started_at: Time.current)
    Warehouse::Raw.db[Warehouse::Raw.loading_table(stream)].select(*columns.map { |c| c[:name].to_sym }).all.map { |row| row.transform_keys(&:to_s) }
  ensure
    Warehouse::Raw.drop_loading_table(stream)
  end

  def fake_load(stream, sync, rows)
    Warehouse::Raw.db[Warehouse::Raw.loading_table(stream)].multi_insert(rows.map { |row| row.merge(_synced_at: sync.started_at, _sync_id: sync.id) })
    rows.size
  end

  def fake_read(connector, rows)
    allow(connector).to receive(:read) { |stream, sync| fake_load(stream, sync, rows) }
  end
end

RSpec.configure { |config| config.include LoadingHelpers }
