class Stream < ApplicationRecord
  belongs_to :source
  has_many :syncs, dependent: :destroy

  validates :schema_name, presence: true
  validates :name, presence: true, uniqueness: { scope: [ :source_id, :schema_name ] }
  validates :destination_table, presence: true, uniqueness: true, length: { maximum: 63 },
                                format: { with: /\A[a-z][a-z0-9_]*\z/ }

  scope :active, -> { where(removed_at: nil) }
  scope :to_sync, -> { active.where(selected: true) }

  def removed?
    removed_at.present?
  end

  def sync!
    sync = syncs.create!(started_at: Time.current)
    count = 0

    if updated_at_attr.present?
      Warehouse::Raw.create_or_update_table(self)
      newest = nil

      source.connector_instance.read(self) do |batch|
        Warehouse::Raw.load(self, batch)
        count += batch.size
      end

      newest = Warehouse::Raw.db[Warehouse::Raw.table(self)].max(updated_at_attr.to_sym)
      update!(last_sync: newest.iso8601(6)) if newest
    else
      Warehouse::Raw.create_loading_table(self)

      source.connector_instance.read(self) do |batch|
        Warehouse::Raw.load_loading(self, batch)
        count += batch.size
      end

      Warehouse::Raw.swap(self)
    end

    sync.update!(status: "succeeded", rows_loaded: count, finished_at: Time.current)
    sync
  rescue => e
    Warehouse::Raw.drop_loading_table(self)
    sync&.update!(status: "failed", error: e.message, finished_at: Time.current)
    raise
  end

  def self.destination_table_for(source_name, schema_name, table_name)
    ([ source_name, schema_name, table_name ] - [ "public" ]).join("__")
  end

  def self.available_destination_table(base)
    candidate = base
    suffix = 1
    candidate = "#{base}_#{suffix += 1}" while exists?(destination_table: candidate)
    candidate
  end
end
