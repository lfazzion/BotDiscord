# frozen_string_literal: true

FactoryBot.define do
  factory :news_article do
    title { Faker::Lorem.sentence }
    link { Faker::Internet.url }
    source { %w[tech games movies].sample }
    pub_date { Time.current }
    description { Faker::Lorem.paragraph }
  end
end
