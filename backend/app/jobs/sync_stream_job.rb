class SyncStreamJob < ApplicationJob
  queue_as :default

  retry_on Connectors::ConnectionError, wait: :polynomially_longer, attempts: 5
  discard_on Stream::SyncInProgress, Stream::GoneFromSource

  def perform(stream)
    stream.sync!
  end
end
