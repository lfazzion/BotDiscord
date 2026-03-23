FactoryBot.define do
  factory :external_catalog do
    source { %w[tmdb igdb anilist].sample }
    external_id { Faker::Number.number(digits: 6).to_s }
    title { Faker::Movie.title }
    media_type { %w[movie tv game anime].sample }
    description { Faker::Lorem.paragraph }
    release_date { Faker::Date.between(from: 1.year.ago, to: 1.year.from_now) }
    popularity { Faker::Number.between(from: 1.0, to: 100.0) }
    vote_average { Faker::Number.between(from: 1.0, to: 10.0) }
    vote_count { Faker::Number.between(from: 10, to: 10_000) }
    poster_url { Faker::Internet.url(path: "/poster.jpg") }
    genres { %w[Action Comedy Drama].sample(2).join(",") }
    metadata { {} }
    original_language { %w[en ja pt].sample }
    adult { false }
    status { %w[upcoming released airing].sample }

    trait :tmdb do
      source { "tmdb" }
      media_type { %w[movie tv].sample }
    end

    trait :igdb do
      source { "igdb" }
      media_type { "game" }
    end

    trait :anilist do
      source { "anilist" }
      media_type { "anime" }
    end

    trait :with_nil_metrics do
      popularity { nil }
      vote_average { nil }
      vote_count { nil }
    end
  end
end
