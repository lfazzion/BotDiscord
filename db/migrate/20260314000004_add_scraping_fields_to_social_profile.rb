# frozen_string_literal: true

class AddScrapingFieldsToSocialProfile < ActiveRecord::Migration[8.0]
  def change
    add_column :social_profiles, :last_collected_at, :datetime unless column_exists?(:social_profiles, :last_collected_at)
    add_column :social_profiles, :collection_status, :string, default: 'pending' unless column_exists?(:social_profiles, :collection_status)
    add_column :social_profiles, :platform_url, :string unless column_exists?(:social_profiles, :platform_url)
    add_column :social_profiles, :bio, :text unless column_exists?(:social_profiles, :bio)
    add_column :social_profiles, :verified, :boolean, default: false unless column_exists?(:social_profiles, :verified)
  end
end
