
  test "R8-Item5: rejeita chave desconhecida em nested discord" do
    registry = Skills::Registry.new
    assert_raises Skills::Registry::ConfigError do
      registry.fetch("nested-unknown-key")
    end
  end
