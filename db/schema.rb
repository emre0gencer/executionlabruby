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

ActiveRecord::Schema[8.1].define(version: 2026_01_21_000000) do
  create_table "execution_traces", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "execution_id", null: false
    t.string "opcode", null: false
    t.integer "pc", null: false
    t.json "snapshot"
    t.integer "step", null: false
    t.datetime "updated_at", null: false
    t.index ["execution_id", "step"], name: "index_execution_traces_on_execution_id_and_step", unique: true
    t.index ["execution_id"], name: "index_execution_traces_on_execution_id"
  end

  create_table "executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.json "metrics"
    t.integer "program_id", null: false
    t.json "result"
    t.integer "runtime_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["program_id"], name: "index_executions_on_program_id"
    t.index ["runtime_id"], name: "index_executions_on_runtime_id"
    t.index ["status"], name: "index_executions_on_status"
  end

  create_table "programs", force: :cascade do |t|
    t.json "bytecode"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "instruction_set"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "runtimes", force: :cascade do |t|
    t.string "adapter_class", null: false
    t.json "config"
    t.datetime "created_at", null: false
    t.string "instruction_set", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["instruction_set"], name: "index_runtimes_on_instruction_set"
  end

  add_foreign_key "execution_traces", "executions"
  add_foreign_key "executions", "programs"
  add_foreign_key "executions", "runtimes"
end
