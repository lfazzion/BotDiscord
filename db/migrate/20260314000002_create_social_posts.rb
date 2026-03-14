class CreateSocialPosts < ActiveRecord::Migration[8.0]
  def change
    create_table :social_posts do |t|
      t.references :social_profile, null: false, foreign_key: true
      t.string :platform_post_id, null: false
      t.string :post_type, null: false
      t.text :content
      t.bigint :likes_count
      t.bigint :comments_count
      t.bigint :shares_count
      t.bigint :views_count
      t.datetime :posted_at

      t.timestamps
    end

    add_index :social_posts, [:social_profile_id, :platform_post_id], unique: true
    add_index :social_posts, :post_type
    add_index :social_posts, :posted_at
  end
end
