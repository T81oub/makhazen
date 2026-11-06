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
    allow(connector).to receive(:discover) do
      [ { schema: stream.schema_name, name: stream.name, columns: stream.source_columns, primary_key: stream.source_primary_key } ]
    end
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

  it "keeps the previous copy when a sync fails" do
    stream.sync!
    allow(connector).to receive(:read).and_raise(Connectors::ConnectionError, "connection lost")

    expect { stream.sync! }.to raise_error(Connectors::ConnectionError)
    expect(raw_table.count).to eq(3)
  end

  it "never leaves a half-loaded table" do
    stream.sync!
    allow(connector).to receive(:read) do |_stream, &block|
      block.call([ { actor_id: 9, first_name: "NEW" } ])
      raise Connectors::ConnectionError, "connection lost"
    end

    expect { stream.sync! }.to raise_error(Connectors::ConnectionError)
    expect(raw_table.order(:actor_id).select_map(:first_name)).to eq(%w[PENELOPE NICK ED])
  end

  context "with updated_at_attr (incremental)" do
    let(:monday) { Time.utc(2026, 10, 26, 9, 0, 0) }
    let(:tuesday) { Time.utc(2026, 10, 27, 9, 0, 0) }
    let(:stream) do
      source.streams.create!(
        schema_name: "public",
        name: "actor",
        destination_table: "pagila__actor",
        source_columns: [
          { "name" => "actor_id", "type" => "integer", "nullable" => false },
          { "name" => "first_name", "type" => "text", "nullable" => false },
          { "name" => "last_update", "type" => "timestamp with time zone", "nullable" => false }
        ],
        source_primary_key: [ "actor_id" ],
        updated_at_attr: "last_update"
      )
    end

    before do
      allow(connector).to receive(:read).and_yield([
        { actor_id: 1, first_name: "PENELOPE", last_update: monday },
        { actor_id: 2, first_name: "NICK", last_update: monday }
      ])
    end

    it "saves the newest value as last_sync" do
      stream.sync!
      expect(Time.iso8601(stream.reload.last_sync)).to eq(monday)
    end

    it "updates changed rows and adds new ones, without duplicates" do
      stream.sync!
      allow(connector).to receive(:read).and_yield([
        { actor_id: 1, first_name: "PENNY", last_update: tuesday },
        { actor_id: 3, first_name: "ED", last_update: tuesday }
      ])
      stream.sync!

      expect(raw_table.order(:actor_id).select_map(:first_name)).to eq(%w[PENNY NICK ED])
      expect(Time.iso8601(stream.reload.last_sync)).to eq(tuesday)
    end

    it "stamps an updated row with the sync that changed it" do
      first = stream.sync!
      allow(connector).to receive(:read).and_yield([ { actor_id: 1, first_name: "PENNY", last_update: tuesday } ])
      second = stream.sync!

      expect(raw_table.order(:actor_id).select_map(:_sync_id)).to eq([ second.id, first.id ])
    end

    it "keeps every row and last_sync when nothing changed" do
      stream.sync!
      allow(connector).to receive(:read)
      sync = stream.sync!

      expect(sync.rows_loaded).to eq(0)
      expect(raw_table.count).to eq(2)
      expect(Time.iso8601(stream.reload.last_sync)).to eq(monday)
    end

    it "does not move last_sync when a sync fails" do
      stream.sync!
      allow(connector).to receive(:read).and_raise(Connectors::ConnectionError, "connection lost")

      expect { stream.sync! }.to raise_error(Connectors::ConnectionError)
      expect(Time.iso8601(stream.reload.last_sync)).to eq(monday)
      expect(stream.syncs.last).to be_failed
    end

    it "can switch a full refresh stream to incremental" do
      stream.update!(updated_at_attr: nil)
      stream.sync!
      stream.update!(updated_at_attr: "last_update")
      allow(connector).to receive(:read).and_yield([ { actor_id: 1, first_name: "PENNY", last_update: tuesday } ])
      stream.sync!

      expect(raw_table.order(:actor_id).select_map(:first_name)).to eq(%w[PENNY NICK])
    end
  end

  context "when the connector says the file has not changed" do
    it "keeps the previous copy" do
      stream.sync!
      allow(connector).to receive(:read).and_return(:unchanged)
      sync = stream.sync!

      expect(sync).to be_succeeded
      expect(sync.rows_loaded).to eq(0)
      expect(raw_table.count).to eq(3)
    end
  end

  it "saves the sha256 the connector found" do
    allow(connector).to receive(:read) do |s, &block|
      block.call([ { actor_id: 1, first_name: "PENELOPE" } ])
      s.last_sha256 = "abc123"
    end
    stream.sync!

    expect(stream.reload.last_sha256).to eq("abc123")
  end

  context "when the source adds a column" do
    let(:monday) { Time.utc(2026, 10, 26, 9, 0, 0) }
    let(:tuesday) { Time.utc(2026, 10, 27, 9, 0, 0) }
    let(:role) { { "name" => "role", "type" => "text", "nullable" => true } }
    let(:stream) do
      source.streams.create!(
        schema_name: "public",
        name: "actor",
        destination_table: "pagila__actor",
        source_columns: [
          { "name" => "actor_id", "type" => "integer", "nullable" => false },
          { "name" => "first_name", "type" => "text", "nullable" => false },
          { "name" => "last_update", "type" => "timestamp with time zone", "nullable" => false }
        ],
        source_primary_key: [ "actor_id" ],
        updated_at_attr: "last_update"
      )
    end

    before do
      allow(connector).to receive(:read).and_yield([
        { actor_id: 1, first_name: "ALEX", last_update: monday },
        { actor_id: 2, first_name: "JOHN", last_update: monday }
      ])
    end

    it "adds the column to the stream and to the warehouse table" do
      stream.sync!

      allow(connector).to receive(:discover).and_return([
        { schema: "public", name: "actor", columns: stream.source_columns + [ role ], primary_key: [ "actor_id" ] }
      ])
      allow(connector).to receive(:read).and_yield([
        { actor_id: 3, first_name: "PENELOPE", last_update: tuesday, role: "teacher" }
      ])
      stream.sync!

      expect(stream.reload.source_columns.map { |c| c["name"] }).to eq([ "actor_id", "first_name", "last_update", "role" ])
      expect(raw_table.order(:actor_id).select_map(:role)).to eq([ nil, nil, "teacher" ])
    end
  end

  context "when the table is gone from the source" do
    before { allow(connector).to receive(:discover).and_return([]) }

    it "fails the sync and marks the stream as removed" do
      expect { stream.sync! }.to raise_error(Stream::GoneFromSource)
      expect(stream.syncs.last).to be_failed
      expect(stream.reload).to be_removed
    end
  end

  it "stamps every row with the sync that loaded it" do
    sync = stream.sync!

    expect(raw_table.select_map(:_sync_id)).to all(eq(sync.id))
    expect(raw_table.select_map(:_synced_at)).to all(be_within(1.second).of(sync.started_at))
  end

  context "when an earlier sync was killed while running" do
    let!(:stuck) { stream.syncs.create!(started_at: 1.hour.ago) }

    it "marks it as failed before starting" do
      stream.sync!

      expect(stuck.reload).to be_failed
      expect(stuck.error).to start_with("Interrupted")
      expect(stuck.finished_at).to be_present
    end

    it "leaves the other streams' syncs alone" do
      other = source.streams.create!(schema_name: "public", name: "film", destination_table: "pagila__film")
      running = other.syncs.create!(started_at: 1.hour.ago)
      stream.sync!

      expect(running.reload).to be_running
    end
  end

  context "when another sync of the same stream is running" do
    let(:other) do
      params = ActiveRecord::Base.connection.raw_connection.conninfo_hash
      PG.connect(params.slice(:host, :port, :dbname, :user, :password))
    end

    def lock_free?
      free = other.exec("SELECT pg_try_advisory_lock(#{stream.id})").getvalue(0, 0) == "t"
      other.exec("SELECT pg_advisory_unlock(#{stream.id})") if free
      free
    end

    after { other.close }

    it "refuses to start and leaves the other sync's work alone" do
      other.exec("SELECT pg_advisory_lock(#{stream.id})")

      expect { stream.sync! }.to raise_error(Stream::SyncInProgress)
      expect(stream.syncs).to be_empty
    ensure
      other.exec("SELECT pg_advisory_unlock(#{stream.id})")
    end

    it "releases the lock when the sync succeeds" do
      stream.sync!
      expect(lock_free?).to be(true)
    end

    it "releases the lock when the sync fails" do
      allow(connector).to receive(:read).and_raise(Connectors::ConnectionError, "connection lost")

      expect { stream.sync! }.to raise_error(Connectors::ConnectionError)
      expect(lock_free?).to be(true)
    end
  end
end
