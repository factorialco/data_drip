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

ActiveRecord::Schema[8.1].define(version: 2026_07_31_000002) do
  create_table "data_drip_backfill_run_batches", force: :cascade do |t|
    t.bigint "backfill_run_id", null: false
    t.integer "batch_size", default: 100, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.bigint "finish_id", null: false
    t.bigint "start_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["backfill_run_id", "created_at"], name: "idx_backfill_batches_on_run_and_created_at"
    t.index ["backfill_run_id", "status"], name: "idx_backfill_batches_on_run_and_status"
  end

  create_table "data_drip_backfill_runs", force: :cascade do |t|
    t.integer "amount_of_elements"
    t.string "backfill_class_name", null: false
    t.bigint "backfiller_id", null: false
    t.string "backfiller_name"
    t.integer "batch_size", default: 100, null: false
    t.string "cell_id"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "group_uuid"
    t.json "options", default: {}, null: false
    t.integer "origin", default: 0, null: false
    t.string "origin_cell_id"
    t.integer "processed_count", default: 0, null: false
    t.datetime "start_at", null: false
    t.integer "status", default: 0, null: false
    t.integer "total_count"
    t.datetime "updated_at", null: false
    t.index ["backfiller_id", "created_at"], name: "idx_backfill_runs_on_backfiller_and_created_at"
    t.index ["created_at"], name: "index_data_drip_backfill_runs_on_created_at"
    t.index ["group_uuid", "cell_id"], name: "idx_backfill_runs_on_group_and_cell", unique: true
    t.index ["status"], name: "index_data_drip_backfill_runs_on_status"
  end

  create_table "data_drip_cell_dispatches", force: :cascade do |t|
    t.string "cell_id", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "group_uuid", null: false
    t.json "last_snapshot"
    t.string "last_status"
    t.datetime "last_synced_at"
    t.json "payload", default: {}, null: false
    t.bigint "remote_run_id"
    t.integer "runnable_type", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "unreachable_since"
    t.datetime "updated_at", null: false
    t.index ["group_uuid", "cell_id"], name: "idx_cell_dispatches_on_group_and_cell", unique: true
  end

  create_table "data_drip_script_runs", force: :cascade do |t|
    t.bigint "backfiller_id", null: false
    t.string "backfiller_name"
    t.string "cell_id"
    t.datetime "created_at", null: false
    t.text "error_backtrace"
    t.text "error_message"
    t.datetime "finished_at"
    t.string "group_uuid"
    t.json "inputs", default: {}, null: false
    t.integer "origin", default: 0, null: false
    t.string "origin_cell_id"
    t.text "output"
    t.string "script_class_name", null: false
    t.datetime "start_at", null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["backfiller_id"], name: "index_data_drip_script_runs_on_backfiller_id"
    t.index ["group_uuid", "cell_id"], name: "idx_script_runs_on_group_and_cell", unique: true
    t.index ["status"], name: "index_data_drip_script_runs_on_status"
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
