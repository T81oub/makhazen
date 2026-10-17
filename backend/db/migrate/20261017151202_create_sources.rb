class CreateSources < ActiveRecord::Migration[8.1]
  def change
    create_table :sources do |t|
      t.string :name, null: false
      t.string :connector, null: false
      t.text :config

      t.timestamps
    end
    add_index :sources, :name, unique: true
  end
end
