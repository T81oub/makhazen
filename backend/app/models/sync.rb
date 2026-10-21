class Sync < ApplicationRecord
  belongs_to :stream
  enum :status, { running: "running", succeeded: "succeeded", failed: "failed" }, validate: true

end
