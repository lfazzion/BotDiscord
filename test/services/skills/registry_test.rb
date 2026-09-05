# frozen_string_literal: true

require "test_helper"

class SkillsRegistryTest < ActiveSupport::TestCase
  test "carrega grill-me.yml" do
    registry = Skills::Registry.new
    skill = registry.fetch("grill-me")
    assert_not_nil skill
    assert_equal "grill-me", skill.name
  end

  test "rejeita versão desconhecida" do
    registry = Skills::Registry.new
    assert_raises Skills::Registry::ConfigError do
      registry.fetch("bad-version")
    end
  end

  test "rejeita chave desconhecida" do
    registry = Skills::Registry.new
    assert_raises Skills::Registry::ConfigError do
      registry.fetch("unknown-key")
    end
  end

  test "R8-Item5: rejeita chave desconhecida em nested discord" do
    registry = Skills::Registry.new
    assert_raises Skills::Registry::ConfigError do
      registry.fetch("nested-unknown-key")
    end
  end

  test "produz digest estável" do
    registry = Skills::Registry.new
    skill = registry.fetch("grill-me")
    digest = skill.digest
    assert_match(/\A[a-f0-9]+\z/, digest)
    assert_equal digest, skill.digest
  end

  test "descobre a fixture de segunda skill" do
    registry = Skills::Registry.new
    skill = registry.fetch("second-skill")
    assert_not_nil skill
    assert_equal "second-skill", skill.name
  end

  test "all retorna todas as skills carregadas" do
    registry = Skills::Registry.new
    all = registry.all
    assert_includes all.map(&:name), "grill-me"
    assert_includes all.map(&:name), "second-skill"
  end
end
