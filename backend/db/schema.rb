# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_27_063752) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "sources", force: :cascade do |t|
    t.string "name", null: false
    t.string "connector", null: false
    t.text "config"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_sources_on_name", unique: true
  end

  create_table "streams", force: :cascade do |t|
    t.bigint "source_id", null: false
    t.string "schema_name", null: false
    t.string "name", null: false
    t.jsonb "source_columns", default: [], null: false
    t.jsonb "source_primary_key", default: [], null: false
    t.boolean "selected", default: false, null: false
    t.string "destination_table", null: false
    t.datetime "removed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "updated_at_attr"
    t.string "last_sync"
    t.index ["destination_table"], name: "index_streams_on_destination_table", unique: true
    t.index ["source_id", "schema_name", "name"], name: "index_streams_on_source_id_and_schema_name_and_name", unique: true
    t.index ["source_id"], name: "index_streams_on_source_id"
  end

  create_table "syncs", force: :cascade do |t|
    t.bigint "stream_id", null: false
    t.string "status", default: "running", null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.integer "rows_loaded", default: 0, null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stream_id"], name: "index_syncs_on_stream_id"
  end

  add_foreign_key "streams", "sources"
  add_foreign_key "syncs", "streams"
end
