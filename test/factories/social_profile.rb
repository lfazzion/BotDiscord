FactoryBot.define do
  factory :social_profile do
    platform { %w[twitter instagram youtube tiktok].sample }
    platform_username { Faker::Internet.username(specifier: 5..20) }
    platform_user_id { Faker::Number.number(digits: 10) }
    display_name { Faker::Name.name }
    bio { Faker::Lorem.sentence }
    followers_count { Faker::Number.between(from: 100, to: 1_000_000) }
    following_count { Faker::Number.between(from: 50, to: 10_000) }
    verified { [true, false].sample }
    profile_url { "https://#{platform}.com/#{platform_username}" }

    trait :twitter do
      platform { "twitter" }
    end

    trait :instagram do
      platform { "instagram" }
    end

    trait :youtube do
      platform { "youtube" }
    end

    trait :tiktok do
      platform { "tiktok" }
    end

    trait :verified do
      verified { true }
    end

    trait :with_nil_metrics do
      followers_count { nil }
      following_count { nil }
    end
  end
end
