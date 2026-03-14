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

ActiveRecord::Schema[8.1].define(version: 2026_03_14_000003) do
  create_table "profile_snapshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "followers_count"
    t.bigint "following_count"
    t.bigint "posts_count"
    t.datetime "recorded_at", null: false
    t.integer "social_profile_id", null: false
    t.datetime "updated_at", null: false
    t.index ["recorded_at"], name: "index_profile_snapshots_on_recorded_at"
    t.index ["social_profile_id"], name: "index_profile_snapshots_on_social_profile_id"
  end

  create_table "social_posts", force: :cascade do |t|
    t.bigint "comments_count"
    t.text "content"
    t.datetime "created_at", null: false
    t.bigint "likes_count"
    t.string "platform_post_id", null: false
    t.string "post_type", null: false
    t.datetime "posted_at"
    t.bigint "shares_count"
    t.integer "social_profile_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "views_count"
    t.index ["post_type"], name: "index_social_posts_on_post_type"
    t.index ["posted_at"], name: "index_social_posts_on_posted_at"
    t.index ["social_profile_id", "platform_post_id"], name: "index_social_posts_on_social_profile_id_and_platform_post_id", unique: true
    t.index ["social_profile_id"], name: "index_social_posts_on_social_profile_id"
  end

  create_table "social_profiles", force: :cascade do |t|
    t.string "avatar_url"
    t.text "bio"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.bigint "followers_count"
    t.bigint "following_count"
    t.string "platform", null: false
    t.string "platform_user_id", null: false
    t.string "platform_username", null: false
    t.string "profile_url"
    t.datetime "updated_at", null: false
    t.boolean "verified", default: false
    t.index ["platform", "platform_user_id"], name: "index_social_profiles_on_platform_and_platform_user_id", unique: true
    t.index ["platform"], name: "index_social_profiles_on_platform"
    t.index ["verified"], name: "index_social_profiles_on_verified"
  end

  add_foreign_key "profile_snapshots", "social_profiles"
  add_foreign_key "social_posts", "social_profiles"
end
