class AddUniqueIndexToStreamsDestinationTable < ActiveRecord::Migration[8.1]
  def change
    add_index :streams, :destination_table, unique: true
  end
end
