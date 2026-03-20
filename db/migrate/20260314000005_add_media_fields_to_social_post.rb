# frozen_string_literal: true

class AddMediaFieldsToSocialPost < ActiveRecord::Migration[8.0]
  def change
    add_column :social_posts, :media_urls, :json, default: []
    add_column :social_posts, :video_url, :string
    add_column :social_posts, :thumbnail_url, :string
    add_column :social_posts, :shares_count, :integer
    add_column :social_posts, :views_count, :integer
  end
end
