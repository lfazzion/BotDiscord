# frozen_string_literal: true

class CreateExternalCatalogs < ActiveRecord::Migration[8.0]
  def change
    create_table :external_catalogs do |t|
      t.string  :source,        null: false
      t.string  :external_id,   null: false
      t.string  :title,         null: false
      t.string  :media_type
      t.text    :description
      t.date    :release_date
      t.float   :popularity
      t.float   :vote_average
      t.integer :vote_count
      t.string  :poster_url
      t.string  :genres
      t.json    :metadata,     default: {}
      t.string  :original_language
      t.boolean :adult,        default: false
      t.string  :status

      t.timestamps
    end

    add_index :external_catalogs, [:source, :external_id], unique: true
    add_index :external_catalogs, :source
    add_index :external_catalogs, :media_type
    add_index :external_catalogs, :release_date
  end
end
