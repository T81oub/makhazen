class Stream < ApplicationRecord
  belongs_to :source
  has_many :syncs, dependent: :destroy

  validates :schema_name, presence: true
  validates :name, presence: true, uniqueness: { scope: [ :source_id, :schema_name ] }
  validates :destination_table, presence: true, length: { maximum: 63 },
                                format: { with: /\A[a-z][a-z0-9_]*\z/ }

  scope :active, -> { where(removed_at: nil) }
  scope :to_sync, -> { active.where(selected: true) }

  def removed?
    removed_at.present?
  end

  def sync!
    sync = syncs.create!(started_at: Time.current)

    #TODO: shouldn't drop all the table while sync
    Warehouse::Raw.db.drop_table?(Warehouse::Raw.table(self))
    Warehouse::Raw.create_table(self)

    count = 0

    source.connector_instance.read(self) do |batch|
      Warehouse::Raw.load(self, batch)
      count += batch.size
    end

    sync.update!(status: "succeeded", rows_loaded: count, finished_at: Time.current)
    sync
  rescue => e
    sync&.update!(status: "failed", error: e.message, finished_at: Time.current)
    raise
  end

  def self.destination_table_for(source_name, schema_name, table_name)
    ([ source_name, schema_name, table_name ] - [ "public" ]).join("__")
  end
end
