class CreateSyncs < ActiveRecord::Migration[8.1]
  def change
    create_table :syncs do |t|
      t.references :stream, null: false, foreign_key: true
      t.string :status, null: false, default: "running"
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :rows_loaded, null: false, default: 0
      t.text :error

      t.timestamps
    end
  end
end
