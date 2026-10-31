class SyncDueStreamsJob < ApplicationJob
  queue_as :default

  def perform
    Stream.due.find_each do |stream|
      stream.schedule_next_sync!
      SyncStreamJob.perform_later(stream)
    end
  end
end
