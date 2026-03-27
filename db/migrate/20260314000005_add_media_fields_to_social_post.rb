# frozen_string_literal: true

class AddMediaFieldsToSocialPost < ActiveRecord::Migration[8.0]
  def change
    add_column :social_posts, :media_urls, :json, default: [] unless column_exists?(:social_posts, :media_urls)
    add_column :social_posts, :video_url, :string unless column_exists?(:social_posts, :video_url)
    add_column :social_posts, :thumbnail_url, :string unless column_exists?(:social_posts, :thumbnail_url)
    add_column :social_posts, :shares_count, :integer unless column_exists?(:social_posts, :shares_count)
    add_column :social_posts, :views_count, :integer unless column_exists?(:social_posts, :views_count)
  end
end
