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

ActiveRecord::Schema[8.1].define(version: 2026_11_09_090003) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "audit_events", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.string "action", null: false
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.datetime "created_at", null: false
    t.index ["actor_id"], name: "index_audit_events_on_actor_id"
    t.index ["subject_type", "subject_id"], name: "index_audit_events_on_subject"
  end

  create_table "passkeys", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "external_id", null: false
    t.text "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.string "nickname"
    t.index ["external_id"], name: "index_passkeys_on_external_id", unique: true
    t.index ["user_id"], name: "index_passkeys_on_user_id"
  end

  create_table "recovery_codes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "digest", null: false
    t.index ["digest"], name: "index_recovery_codes_on_digest", unique: true
    t.index ["user_id"], name: "index_recovery_codes_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.boolean "passkey_verified", default: false, null: false
    t.date "expires_on", null: false
    t.string "webauthn_challenge"
    t.index ["expires_on"], name: "index_sessions_on_expires_on"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "taxonomy_fields", force: :cascade do |t|
    t.bigint "taxonomy_version_id", null: false
    t.string "code", null: false
    t.string "group", null: false
    t.string "kind", null: false
    t.string "scope", null: false
    t.integer "position", null: false
    t.string "label", null: false
    t.index ["taxonomy_version_id", "code"], name: "index_taxonomy_fields_on_taxonomy_version_id_and_code", unique: true
    t.index ["taxonomy_version_id"], name: "index_taxonomy_fields_on_taxonomy_version_id"
    t.check_constraint "kind::text = ANY (ARRAY['single'::character varying, 'multi'::character varying, 'text'::character varying, 'integer'::character varying]::text[])", name: "taxonomy_fields_kind_check"
    t.check_constraint "scope::text = ANY (ARRAY['report'::character varying, 'casualty'::character varying]::text[])", name: "taxonomy_fields_scope_check"
  end

  create_table "taxonomy_options", force: :cascade do |t|
    t.bigint "taxonomy_field_id", null: false
    t.string "code", null: false
    t.string "label", null: false
    t.text "definition"
    t.integer "position", null: false
    t.index ["taxonomy_field_id", "code"], name: "index_taxonomy_options_on_taxonomy_field_id_and_code", unique: true
    t.index ["taxonomy_field_id"], name: "index_taxonomy_options_on_taxonomy_field_id"
  end

  create_table "taxonomy_versions", force: :cascade do |t|
    t.integer "number", null: false
    t.datetime "published_at"
    t.index ["number"], name: "index_taxonomy_versions_on_number", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "role", default: "declarant", null: false
    t.date "membership_expires_on"
    t.integer "login_token_version", default: 0, null: false
    t.string "enrollment_code_digest"
    t.date "enrollment_code_expires_on"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["enrollment_code_digest"], name: "index_users_on_enrollment_code_digest", unique: true
    t.check_constraint "role::text = ANY (ARRAY['declarant'::character varying::text, 'analyst'::character varying::text, 'admin'::character varying::text])", name: "users_role_check"
  end

  add_foreign_key "audit_events", "users", column: "actor_id"
  add_foreign_key "passkeys", "users"
  add_foreign_key "recovery_codes", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "taxonomy_fields", "taxonomy_versions"
  add_foreign_key "taxonomy_options", "taxonomy_fields"
end
