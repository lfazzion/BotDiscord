require 'test_helper'

class DiscoveredProfileTest < ActiveSupport::TestCase
  setup do
    @profile = build(:discovered_profile)
  end

  test 'should be valid with valid attributes' do
    assert @profile.valid?
  end

  test 'platform should be present' do
    @profile.platform = nil
    assert_not @profile.valid?
    assert_includes @profile.errors[:platform], "can't be blank"
  end

  test 'username should be present' do
    @profile.username = nil
    assert_not @profile.valid?
    assert_includes @profile.errors[:username], "can't be blank"
  end

  test 'platform and username should be unique together' do
    create(:discovered_profile, platform: 'twitter', username: 'joao')
    duplicate = build(:discovered_profile, platform: 'twitter', username: 'joao')
    assert_not duplicate.valid?
  end

  test 'same username on different platform should be valid' do
    create(:discovered_profile, platform: 'twitter', username: 'joao')
    other = build(:discovered_profile, platform: 'instagram', username: 'joao')
    assert other.valid?
  end

  test 'classification should be in allowed list or nil' do
    @profile.classification = nil
    assert @profile.valid?

    DiscoveredProfile::CLASSIFICATIONS.each do |c|
      @profile.classification = c
      assert @profile.valid?
    end

    @profile.classification = 'INVALID'
    assert_not @profile.valid?
  end

  test 'unclassified scope should return profiles without classification' do
    unclassified = create(:discovered_profile, classification: nil)
    classified = create(:discovered_profile, :classified)

    assert_includes DiscoveredProfile.unclassified, unclassified
    assert_not_includes DiscoveredProfile.unclassified, classified
  end

  test 'stale_classification scope should return old or unclassified' do
    stale = create(:discovered_profile, :stale)
    fresh = create(:discovered_profile, :classified)

    assert_includes DiscoveredProfile.stale_classification, stale
    assert_not_includes DiscoveredProfile.stale_classification, fresh
  end

  test 'prospects scope should return only PATROCINADOR_PROSPECTO' do
    prospecto = create(:discovered_profile, :prospecto)
    concorrente = create(:discovered_profile, :concorrente)

    assert_includes DiscoveredProfile.prospects, prospecto
    assert_not_includes DiscoveredProfile.prospects, concorrente
  end

  test 'should optionally belong to source_profile' do
    source = create(:social_profile)
    dp = create(:discovered_profile, source_profile: source)

    assert_equal source, dp.source_profile
  end

  test 'CLASSIFICATIONS constant should have expected values' do
    assert_equal %w[CONCORRENTE PATROCINADOR_PROSPECTO IGNORAR], DiscoveredProfile::CLASSIFICATIONS
  end

  test 'source_profile can be nil' do
    dp = create(:discovered_profile, source_profile: nil)
    assert_nil dp.source_profile
  end
end
