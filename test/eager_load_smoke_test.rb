# frozen_string_literal: true
#
# RED devera falhar hoje: lib/skills/derive_allowlist.rb define
# `module DeriveAllowlist` (top-level), mas o Zeitwerk (config.autoload_lib
# em config/application.rb:18) espera que lib/skills/derive_allowlist.rb
# defina `Skills::DeriveAllowlist`. Em prod (eager_load=true) isso explode.
require "test_helper"

class EagerLoadSmokeTest < ActiveSupport::TestCase
  test "Skills::DeriveAllowlist é definido após eager_load" do
    Rails.application.eager_load!

    assert_nothing_raised do
      const = Skills::DeriveAllowlist
      assert_kind_of Module, const
    end
  end
end
