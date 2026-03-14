FactoryBot.define do
  factory :profile_snapshot do
    association :social_profile
    followers_count { Faker::Number.between(from: 100, to: 1_000_000) }
    following_count { Faker::Number.between(from: 50, to: 10_000) }
    posts_count { Faker::Number.between(from: 10, to: 10_000) }
    recorded_at { Time.current }

    trait :recent do
      recorded_at { Time.current }
    end

    trait :old do
      recorded_at { 3.hours.ago }
    end

    trait :very_old do
      recorded_at { 3.days.ago }
    end

    trait :with_nil_counts do
      followers_count { nil }
      following_count { nil }
      posts_count { nil }
    end
  end
end
