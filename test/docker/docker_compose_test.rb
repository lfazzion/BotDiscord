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

  test "should have app service" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)
    assert config["services"].key?("app"), "app service not found"
  end

  test "should have jobs service" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)
    assert config["services"].key?("jobs"), "jobs service not found"
  end

  test "should have chrome service" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)
    assert config["services"].key?("chrome"), "chrome service not found"
  end

  test "chrome service should use chromedp/headless-shell image" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)
    image = config["services"]["chrome"]["image"]
    assert_includes image, "chromedp/headless-shell"
  end

  test "chrome service should expose port 9222" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)
    ports = config["services"]["chrome"]["ports"]
    assert_includes ports.join, "9222"
  end

  test "app service should depend on chrome" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)
    depends_on = config["services"]["app"]["depends_on"] || []
    assert_includes depends_on, "chrome"
  end

  test "jobs service should depend on chrome" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)
    depends_on = config["services"]["jobs"]["depends_on"] || []
    assert_includes depends_on, "chrome"
  end

  test "should have sqlite volume" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)
    assert config["volumes"].key?("sqlite_data")
  end

  test "docker-compose version should be 3.8" do
    config = YAML.load_file(DOCKER_COMPOSE_PATH)
    assert_equal "3.8", config["version"]
  end
end
