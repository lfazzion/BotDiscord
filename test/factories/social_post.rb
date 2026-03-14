FactoryBot.define do
  factory :social_post do
    association :social_profile
    platform_post_id { Faker::Number.number(digits: 15) }
    post_type { %w[image video text reel story].sample }
    content { Faker::Lorem.paragraph }
    likes_count { Faker::Number.between(from: 0, to: 100_000) }
    comments_count { Faker::Number.between(from: 0, to: 10_000) }
    shares_count { Faker::Number.between(from: 0, to: 5_000) }
    views_count { Faker::Number.between(from: 0, to: 1_000_000) }
    posted_at { Faker::Time.backward(days: 30) }

    trait :video do
      post_type { "video" }
    end

    trait :image do
      post_type { "image" }
    end

    trait :text do
      post_type { "text" }
      views_count { nil }
    end

    trait :high_engagement do
      likes_count { Faker::Number.between(from: 50_000, to: 500_000) }
      comments_count { Faker::Number.between(from: 1_000, to: 10_000) }
    end

    trait :nil_engagement do
      likes_count { nil }
      comments_count { nil }
      shares_count { nil }
      views_count { nil }
    end

    trait :recent do
      posted_at { Faker::Time.backward(days: 7) }
    end
  end
end
