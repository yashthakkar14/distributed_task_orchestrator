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

ActiveRecord::Schema[7.0].define(version: 2026_02_14_115856) do
  create_table "clients", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.integer "concurrency_limit", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_clients_on_name", unique: true
  end

  create_table "jobs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "priority", default: 0, null: false
    t.string "workload", null: false
    t.integer "attempts", default: 0, null: false
    t.integer "max_retries", default: 3, null: false
    t.text "last_error"
    t.datetime "scheduled_at"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.string "locked_by"
    t.datetime "locked_at"
    t.string "idempotency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id", "status"], name: "idx_jobs_client_status"
    t.index ["client_id"], name: "index_jobs_on_client_id"
    t.index ["idempotency_key"], name: "index_jobs_on_idempotency_key", unique: true
    t.index ["status", "priority", "created_at"], name: "idx_jobs_scheduling"
    t.index ["status", "scheduled_at"], name: "idx_jobs_retry_scheduling"
  end

  add_foreign_key "jobs", "clients"
end
