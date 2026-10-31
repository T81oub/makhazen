class SyncStreamJob < ApplicationJob
  queue_as :default

  def perform(stream)
    stream.sync!
  end
end
