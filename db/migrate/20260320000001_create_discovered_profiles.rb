# frozen_string_literal: true

class CreateDiscoveredProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :discovered_profiles do |t|
      t.string :platform, null: false
      t.string :username, null: false
      t.text :bio
      t.string :profile_url
      t.string :classification
      t.text :classification_reason
      t.references :source_profile, foreign_key: { to_table: :social_profiles }
      t.datetime :classified_at

      t.timestamps
    end

    add_index :discovered_profiles, %i[platform username], unique: true
    add_index :discovered_profiles, :classification
  end
end
