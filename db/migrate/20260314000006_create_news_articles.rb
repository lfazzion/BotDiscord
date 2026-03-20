# frozen_string_literal: true

class CreateNewsArticles < ActiveRecord::Migration[8.0]
  def change
    create_table :news_articles do |t|
      t.string :title
      t.text :description
      t.string :link, null: false
      t.string :source
      t.datetime :pub_date
      t.string :query_used

      t.timestamps
    end

    add_index :news_articles, :link, unique: true
    add_index :news_articles, :pub_date
  end
end
