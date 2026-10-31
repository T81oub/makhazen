class AddScheduleToStreams < ActiveRecord::Migration[8.1]
  def change
    add_column :streams, :sync_every, :string, null: false, default: "daily"
    add_column :streams, :next_sync_at, :datetime
    add_index :streams, :next_sync_at
  end
end
