require "rails_helper"

RSpec.describe SyncDueStreamsJob do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:source) do
    Source.create!(name: "waste", connector: "data_gouv", config: { "dataset" => "waste-2022" })
  end

  def create_stream(name, **params)
    source.streams.create!(
      { schema_name: "res-zip", name: name, destination_table: "waste__#{name}", selected: true }.merge(params)
    )
  end

  before { ActiveJob::Base.queue_adapter = :test }

  it "starts a sync for a stream that was never synced" do
    stream = create_stream("never")
    expect { described_class.perform_now }.to have_enqueued_job(SyncStreamJob).with(stream)
  end

  it "starts a sync for a stream that is due" do
    stream = create_stream("due", next_sync_at: 1.minute.ago)
    expect { described_class.perform_now }.to have_enqueued_job(SyncStreamJob).with(stream)
  end

  it "waits for a stream that is not due yet" do
    create_stream("later", next_sync_at: 1.hour.from_now)
    expect { described_class.perform_now }.not_to have_enqueued_job(SyncStreamJob)
  end

  it "skips streams that are not selected or removed" do
    create_stream("unselected", selected: false)
    create_stream("removed", removed_at: Time.current)
    expect { described_class.perform_now }.not_to have_enqueued_job(SyncStreamJob)
  end

  it "plans the next sync from the stream's frequency" do
    hourly = create_stream("hourly", sync_every: "hourly")
    monthly = create_stream("monthly", sync_every: "monthly")

    freeze_time do
      described_class.perform_now
      expect(hourly.reload.next_sync_at).to eq(1.hour.from_now)
      expect(monthly.reload.next_sync_at).to eq(1.month.from_now)
    end
  end

  it "does not start the same stream twice in a row" do
    create_stream("once")
    described_class.perform_now
    expect { described_class.perform_now }.not_to have_enqueued_job(SyncStreamJob)
  end
end
