class Stream < ApplicationRecord
  belongs_to :source

  validates :schema_name, presence: true
  validates :name, presence: true, uniqueness: { scope: [ :source_id, :schema_name ] }
  validates :destination_table, presence: true, length: { maximum: 63 },
                                format: { with: /\A[a-z][a-z0-9_]*\z/ }

  scope :active, -> { where(removed_at: nil) }
  scope :to_sync, -> { active.where(selected: true) }

  def removed?
    removed_at.present?
  end
end
