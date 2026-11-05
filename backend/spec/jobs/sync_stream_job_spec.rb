require "rails_helper"

RSpec.describe SyncStreamJob do
  include ActiveJob::TestHelper

  let(:source) { Source.create!(name: "waste", connector: "data_gouv", config: { "dataset" => "waste-2022" }) }
  let(:stream) { source.streams.create!(schema_name: "res-zip", name: "data", destination_table: "waste__data") }

  before { ActiveJob::Base.queue_adapter = :test }

  it "syncs the stream" do
    expect(stream).to receive(:sync!)
    described_class.perform_now(stream)
  end

  it "tries again later when the source can't be reached" do
    allow(stream).to receive(:sync!).and_raise(Connectors::ConnectionError)
    expect { described_class.perform_now(stream) }.to have_enqueued_job(described_class).with(stream)
  end

  it "does not try again when another sync of the stream is running" do
    allow(stream).to receive(:sync!).and_raise(Stream::SyncInProgress)
    expect { described_class.perform_now(stream) }.not_to have_enqueued_job
  end

  it "does not try again when the table is gone from the source" do
    allow(stream).to receive(:sync!).and_raise(Stream::GoneFromSource)
    expect { described_class.perform_now(stream) }.not_to have_enqueued_job
  end
end
