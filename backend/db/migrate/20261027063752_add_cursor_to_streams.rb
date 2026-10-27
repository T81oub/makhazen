class AddCursorToStreams < ActiveRecord::Migration[8.1]
  def change
    add_column :streams, :updated_at_attr, :string
    add_column :streams, :last_sync, :string
  end
end
