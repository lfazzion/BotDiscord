# frozen_string_literal: true

class AddShortcodeAndIsPrivate < ActiveRecord::Migration[8.1]
  def change
    add_column :social_posts, :shortcode, :string unless column_exists?(:social_posts, :shortcode)
    add_column :social_profiles, :is_private, :boolean, default: false unless column_exists?(:social_profiles, :is_private)
    add_column :social_profiles, :posts_count, :integer, default: 0, null: false unless column_exists?(:social_profiles, :posts_count)
  end
end
