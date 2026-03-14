class CreateProfileSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :profile_snapshots do |t|
      t.references :social_profile, null: false, foreign_key: true
      t.bigint :followers_count
      t.bigint :following_count
      t.bigint :posts_count
      t.datetime :recorded_at, null: false

      t.timestamps
    end

    add_index :profile_snapshots, :social_profile_id
    add_index :profile_snapshots, :recorded_at
  end
end
