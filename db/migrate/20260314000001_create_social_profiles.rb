class CreateSocialProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :social_profiles do |t|
      t.string :platform, null: false
      t.string :platform_username, null: false
      t.string :platform_user_id, null: false
      t.string :display_name
      t.text :bio
      t.bigint :followers_count
      t.bigint :following_count
      t.boolean :verified, default: false
      t.string :profile_url
      t.string :avatar_url

      t.timestamps
    end

    add_index :social_profiles, [:platform, :platform_user_id], unique: true
    add_index :social_profiles, :platform
    add_index :social_profiles, :verified
  end
end
