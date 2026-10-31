require "rails_helper"

RSpec.describe SyncStreamJob do
  it "syncs the stream" do
    stream = instance_double(Stream)
    expect(stream).to receive(:sync!)

    described_class.perform_now(stream)
  end
end
