class CreateStreams < ActiveRecord::Migration[8.1]
  def change
    create_table :streams do |t|
      t.references :source, null: false, foreign_key: true
      t.string :schema_name, null: false
      t.string :name, null: false
      t.jsonb :source_columns, null: false, default: []
      t.jsonb :source_primary_key, null: false, default: []
      t.boolean :selected, null: false, default: false
      t.string :destination_table, null: false
      t.datetime :removed_at

      t.timestamps
    end

    add_index :streams, [ :source_id, :schema_name, :name ], unique: true
  end
end
