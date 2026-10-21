require "rails_helper"

# Uses a fake connector, but a real (test) warehouse.
RSpec.describe Stream, "#sync!", :integration do
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
  let(:stream) do
    source.streams.create!(
      schema_name: "public",
      name: "actor",
      destination_table: "pagila__actor",
      source_columns: [
        { "name" => "actor_id", "type" => "integer", "nullable" => false },
        { "name" => "first_name", "type" => "text", "nullable" => false }
      ]
    )
  end
  let(:raw_table) { Warehouse::Base.db[Sequel[:raw][:pagila__actor]] }
  let(:connector) { double("connector") }

  before do
    allow(stream.source).to receive(:connector_instance).and_return(connector)
    allow(connector).to receive(:read)
      .and_yield([ { actor_id: 1, first_name: "PENELOPE" }, { actor_id: 2, first_name: "NICK" } ])
      .and_yield([ { actor_id: 3, first_name: "ED" } ])
  end

  after { Warehouse::Base.db.drop_table?(Sequel[:raw][:pagila__actor]) }

  it "copies every row into the raw table" do
    stream.sync!
    expect(raw_table.order(:actor_id).select_map(:first_name)).to eq(%w[PENELOPE NICK ED])
  end

  it "records a succeeded sync with the number of rows" do
    sync = stream.sync!
    expect(sync).to be_succeeded
    expect(sync.rows_loaded).to eq(3)
    expect(sync.started_at).to be_present
    expect(sync.finished_at).to be_present
  end

  it "replaces the previous copy (full refresh)" do
    stream.sync!
    stream.sync!
    expect(raw_table.count).to eq(3)
  end

  context "when reading fails" do
    before do
      allow(connector).to receive(:read).and_raise(Connectors::ConnectionError, "connection lost")
    end

    it "records a failed sync with the error" do
      expect { stream.sync! }.to raise_error(Connectors::ConnectionError)
      sync = stream.syncs.last
      expect(sync).to be_failed
      expect(sync.error).to include("connection lost")
      expect(sync.finished_at).to be_present
    end
  end
end
