require "test_helper"

class TheLocalProviderTest < ActiveSupport::TestCase
  GEM_ROOT = File.expand_path("..", __dir__)

  def test_the_trio_of_locals_is_committed
    assert_equal %w[event_engine-delivery-develop.md event_engine-delivery-info.md event_engine-delivery-install.md],
                 Dir.children(File.join(GEM_ROOT, "the_local", "agents")).sort
  end
end
