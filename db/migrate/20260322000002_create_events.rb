# frozen_string_literal: true

class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events do |t|
      t.string  :title,           null: false
      t.text    :description
      t.string  :source
      t.string  :source_url
      t.string  :location
      t.date    :start_date
      t.date    :end_date
      t.string  :event_type
      t.string  :image_url
      t.string  :organizer

      t.timestamps
    end

    add_index :events, :source_url, unique: true
    add_index :events, :event_type
    add_index :events, :start_date
    add_index :events, :location
  end
end
