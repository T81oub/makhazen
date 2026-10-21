require "rails_helper"

RSpec.describe Sync, type: :model do
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
    source.streams.create!(schema_name: "public", name: "rental", destination_table: "pagila__rental")
  end

  it "starts as running with no rows loaded" do
    sync = stream.syncs.create!
    expect(sync).to be_running
    expect(sync.rows_loaded).to eq(0)
  end

  it "requires a stream" do
    sync = Sync.new
    expect(sync).not_to be_valid
    expect(sync.errors[:stream]).to include("must exist")
  end

  it "only accepts running, succeeded or failed" do
    expect(stream.syncs.build(status: "succeeded")).to be_valid
    expect(stream.syncs.build(status: "failed")).to be_valid
    expect(stream.syncs.build(status: "paused")).not_to be_valid
  end

  it "is deleted with its stream" do
    stream.syncs.create!
    expect { stream.destroy }.to change(Sync, :count).by(-1)
  end
end
