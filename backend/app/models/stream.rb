class Stream < ApplicationRecord
  class GoneFromSource < StandardError; end

  belongs_to :source
  has_many :syncs, dependent: :destroy

  validates :schema_name, presence: true
  validates :name, presence: true, uniqueness: { scope: [ :source_id, :schema_name ] }
  validates :destination_table, presence: true, uniqueness: true, length: { maximum: 63 },
                                format: { with: /\A[a-z][a-z0-9_]*\z/ }

  SYNC_INTERVALS = { "hourly" => 1.hour, "daily" => 1.day, "monthly" => 1.month }.freeze

  enum :sync_every, { hourly: "hourly", daily: "daily", monthly: "monthly" }, validate: true

  scope :active, -> { where(removed_at: nil) }
  scope :to_sync, -> { active.where(selected: true) }
  scope :due, -> { to_sync.where("next_sync_at IS NULL OR next_sync_at <= ?", Time.current) }

  def removed?
    removed_at.present?
  end

  def schedule_next_sync!
    update!(next_sync_at: Time.current + SYNC_INTERVALS.fetch(sync_every))
  end

  def sync!
    sync = syncs.create!(started_at: Time.current)
    count = 0

    table = source.connector_instance.discover.find { |t| t[:schema] == schema_name && t[:name] == name }

    unless table
      update!(removed_at: Time.current)
      raise GoneFromSource, "#{schema_name}.#{name} is no longer in the source"
    end

    update!(source_columns: table[:columns].map(&:stringify_keys), source_primary_key: table[:primary_key])

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

      result = source.connector_instance.read(self) do |batch|
        Warehouse::Raw.load_loading(self, batch)
        count += batch.size
      end

      if result == :unchanged
        Warehouse::Raw.drop_loading_table(self)
      else
        Warehouse::Raw.swap(self)
        save!
      end
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
