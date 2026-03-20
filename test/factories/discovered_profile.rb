FactoryBot.define do
  factory :discovered_profile do
    platform { %w[twitter instagram youtube].sample }
    username { Faker::Internet.username(specifier: 3..15) }
    bio { Faker::Lorem.sentence }
    profile_url { "https://#{platform}.com/#{username}" }

    trait :classified do
      classification { DiscoveredProfile::CLASSIFICATIONS.sample }
      classification_reason { Faker::Lorem.sentence }
      classified_at { Time.current }
    end

    trait :concorrente do
      classification { 'CONCORRENTE' }
      classification_reason { 'Influenciador do mesmo nicho' }
      classified_at { Time.current }
    end

    trait :prospecto do
      classification { 'PATROCINADOR_PROSPECTO' }
      classification_reason { 'Marca relevante para parceria' }
      classified_at { Time.current }
    end

    trait :ignorado do
      classification { 'IGNORAR' }
      classification_reason { 'Bot ou spam' }
      classified_at { Time.current }
    end

    trait :stale do
      classification { 'IGNORAR' }
      classified_at { 10.days.ago }
    end
  end
end
