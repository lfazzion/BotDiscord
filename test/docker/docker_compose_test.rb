require "test_helper"
require "yaml"

class DockerComposeTest < ActiveSupport::TestCase
  DOCKER_COMPOSE_PATH = Rails.root.join("docker", "docker-compose.yml")

  test "docker-compose.yml should exist" do
    assert File.exist?(DOCKER_COMPOSE_PATH), "docker-compose.yml not found"
  end

  test "docker-compose.yml should be valid YAML" do
    assert_nothing_raised do
      YAML.load_file(DOCKER_COMPOSE_PATH)
    end
  end

  test "should have required services" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)
    services = config["services"]

    assert services.key?("app"), "app service not found"
    assert services.key?("jobs"), "jobs service not found"
    assert services.key?("chrome"), "chrome service not found"
  end

  test "app service should have correct configuration" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)
    app = config["services"]["app"]

    assert_includes app["command"], "rails server"
    assert_includes app["networks"], "internal"
    assert_equal "3000:3000", app["ports"].first
  end

  test "jobs service should run solid queue via bin/jobs" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)
    jobs = config["services"]["jobs"]

    assert_includes jobs["command"], "jobs start"
    assert_includes jobs["networks"], "internal"
  end

  test "chrome service should use chromedp/headless-shell" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)
    chrome = config["services"]["chrome"]

    assert_includes chrome["image"], "chromedp/headless-shell"
    assert_includes chrome["ports"].join, "9222"
    assert_equal "2gb", chrome["shm_size"]
    assert_includes chrome["networks"], "internal"
  end

  test "app and jobs should depend on chrome service" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)

    app_deps = config["services"]["app"]["depends_on"] || {}
    jobs_deps = config["services"]["jobs"]["depends_on"] || {}

    assert app_deps.key?("chrome"), "app should depend on chrome"
    assert jobs_deps.key?("chrome"), "jobs should depend on chrome"
  end

  test "services should use internal network" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)

    config["services"].each do |name, service|
      assert_includes service["networks"], "internal", "#{name} should use internal network"
    end

    assert config["networks"].key?("internal"), "internal network should be defined"
  end

  test "services should have restart policy" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)

    config["services"].each do |name, service|
      assert service["restart"], "#{name} should have restart policy"
    end
  end

  test "all services should have CHROME_HOST and CHROME_PORT environment" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)

    %w[app jobs].each do |service_name|
      env = config["services"][service_name]["environment"] || {}
      assert env["CHROME_HOST"], "#{service_name} should have CHROME_HOST env"
      assert env["CHROME_PORT"], "#{service_name} should have CHROME_PORT env"
    end
  end

  test "docker-compose version should be 3.8" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)
    assert_equal "3.8", config["version"]
  end
end
