ActiveRecord::Schema[8.1].define(version: 2026_10_17_151202) do
  enable_extension "pg_catalog.plpgsql"

  create_table "sources", force: :cascade do |t|
    t.string "name", null: false
    t.string "connector", null: false
    t.text "config"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_sources_on_name", unique: true
  end
end
