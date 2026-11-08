require "rails_helper"

# Uses a fake connector, but a real (test) warehouse.
RSpec.describe Source, "#sync!", :integration do
  let(:source) do
    Source.create!(
      name: "pagila",
      connector: "postgres",
      config: {
        "host" => "source_db",
        "port" => 5432,
        "database" => "pagila",
        "username" => "makhazen_reader",
        "password" => "s3cret-password"
      }
    )
  end
  let(:columns) { [ { "name" => "id", "type" => "integer", "nullable" => false } ] }
  let(:connector) { double("connector") }

  def add_stream(name, **attributes)
    source.streams.create!(
      schema_name: "public", name: name, destination_table: "pagila__#{name}",
      source_columns: columns, **attributes
    )
  end

  let!(:actor) { add_stream("actor", selected: true) }
  let!(:film) { add_stream("film", selected: true) }
  let!(:city) { add_stream("city", selected: false) }
  let!(:old_table) { add_stream("old_table", selected: true, removed_at: 1.day.ago) }

  before do
    allow(source).to receive(:connector_instance).and_return(connector)
    allow(connector).to receive(:discover) do
      source.streams.map { |s| { schema: s.schema_name, name: s.name, columns: s.source_columns, primary_key: s.source_primary_key } }
    end
    fake_read(connector, [ { id: 1 }, { id: 2 } ])
  end

  after do
    %i[pagila__actor pagila__film pagila__city pagila__old_table].each do |table|
      Warehouse::Base.db.drop_table?(Sequel[:raw][table])
    end
  end

  it "syncs only the selected streams that still exist in the source" do
    source.sync!
    expect(Sync.all.map(&:stream)).to contain_exactly(actor, film)
  end

  it "returns one succeeded sync per stream" do
    syncs = source.sync!
    expect(syncs.map(&:status)).to eq(%w[succeeded succeeded])
  end

  it "keeps going when one stream fails" do
    allow(connector).to receive(:read) do |stream, sync|
      raise Connectors::ConnectionError, "connection lost" if stream.name == "actor"

      fake_load(stream, sync, [ { id: 1 } ])
    end

    syncs = source.sync!
    expect(syncs.map { |sync| [ sync.stream.name, sync.status ] })
      .to contain_exactly([ "actor", "failed" ], [ "film", "succeeded" ])
  end
end
