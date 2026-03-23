# frozen_string_literal: true

class AddScrapingFieldsToSocialProfile < ActiveRecord::Migration[8.0]
  def change
    add_column :social_profiles, :last_collected_at, :datetime
    add_column :social_profiles, :collection_status, :string, default: 'pending'
    add_column :social_profiles, :platform_url, :string
    add_column :social_profiles, :bio, :text unless column_exists?(:social_profiles, :bio)
    add_column :social_profiles, :verified, :boolean, default: false unless column_exists?(:social_profiles, :verified)
  end
end
