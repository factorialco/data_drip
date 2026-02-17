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

ActiveRecord::Schema[8.1].define(version: 2025_11_20_142547) do
  create_table "data_drip_backfill_run_batches", force: :cascade do |t|
    t.bigint "backfill_run_id", null: false
    t.integer "batch_size", default: 100, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.bigint "finish_id", null: false
    t.bigint "start_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["backfill_run_id"], name: "index_data_drip_backfill_run_batches_on_backfill_run_id"
    t.index ["status"], name: "index_data_drip_backfill_run_batches_on_status"
  end

  create_table "data_drip_backfill_runs", force: :cascade do |t|
    t.integer "amount_of_elements"
    t.string "backfill_class_name", null: false
    t.bigint "backfiller_id", null: false
    t.integer "batch_size", default: 100, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.json "options", default: {}, null: false
    t.integer "processed_count", default: 0, null: false
    t.datetime "start_at", null: false
    t.integer "status", default: 0, null: false
    t.integer "total_count"
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_data_drip_backfill_runs_on_status"
  end

  create_table "employees", force: :cascade do |t|
    t.integer "age"
    t.date "birthday"
    t.datetime "created_at", null: false
    t.string "name"
    t.string "role"
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "data_drip_backfill_run_batches", "data_drip_backfill_runs", column: "backfill_run_id"
end
