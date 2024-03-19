module Rosi
  extend self

  def load(service, ref = nil)
    require_relative './iruby/ostream'

    if not services().include?(service)
      raise "service #{service.inspect} not found, allowed services are: #{services().inspect}"
    end

    service = service_presets()[service]
    dir = Dir.mktmpdir("nj-")

    log("using temp dir #{dir}")
    Dir.chdir(dir) do
      $VERBOSE = nil
        log("cloning repo #{service[:git]}")
        `git clone --depth 1 #{service[:git]} 2>&1`

        if ref
          log("using ref #{ref}")
          Dir.chdir(git_dir(service[:git])) do
            `git fetch --depth=1 origin #{ref}:#{ref} 2>&1`
            `git checkout #{ref} 2>&1`
          end
        else
          log("using ref main")
        end

        set_env()

        root_path = "#{dir}/#{git_dir(service[:git])}"
        log("running bundle install in #{root_path}")
        Dir.chdir(root_path) { puts `bundle install` }

        log("cleaning up default gems")
        isolate_gems(service[:isolate_gems] || [])

        service[:before_load].call if service[:before_load]

        log("loading app")
        require_relative "#{root_path}/config/boot"
        require_relative "#{root_path}/config/application"

        Dir.chdir(root_path) do
            Rails.application.require_environment!
        end
    end

    log("done")
    "#{dir}/#{git_dir(service[:git])}"
  end

  def configure_db(config)
    new_config = ActiveRecord::Base.configurations[ENV['RAILS_ENV']].merge(config)
    ActiveRecord::Base.establish_connection(new_config)
  end

  def services()
    service_presets().keys
  end

  def service_presets()
    {
      user: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_user_service.git",
        isolate_gems: default_isolated_gems(),
        before_load: -> {}
      },
      catalog: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_catalog_service.git",
        isolate_gems: default_isolated_gems(),
        before_load: -> {}
      },
      mybusiness: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_my_business_service.git",
        isolate_gems: default_isolated_gems(),
        before_load: -> {}
      },
      cart: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_cart_service.git",
        isolate_gems: default_isolated_gems(),
        before_load: -> {}
      },
      inventory: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_inventory_service.git",
        isolate_gems: default_isolated_gems(),
        before_load: -> {}
      },
      oms: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_oms_service.git",
        isolate_gems: default_isolated_gems(),
        before_load: -> {}
      },
      payment: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_payment_management_service.git",
        isolate_gems: default_isolated_gems(),
        before_load: -> {}
      },
      rewards: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_rewards_service.git",
        isolate_gems: default_isolated_gems(),
        before_load: -> {}
      },
      tax: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_tax_service.git",
        isolate_gems: default_isolated_gems(),
        before_load: -> {}
      },
      virtual: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_virtual_fulfillment_service.git",
        isolate_gems: default_isolated_gems(),
        before_load: -> {}
      },
      email: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_email_service.git",
        isolate_gems: default_isolated_gems(),
        before_load: -> {}
      },
      ugc: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_ugc_service.git",
        isolate_gems: default_isolated_gems(),
        before_load: -> {}
      },
      credits: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_credits_service.git",
        isolate_gems: default_isolated_gems(),
        before_load: -> {}
      },
      subscription: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_subscription_service.git",
        isolate_gems: default_isolated_gems(),
        before_load: -> {}
      },
      notification: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_notification_service.git",
        isolate_gems: default_isolated_gems(),
        before_load: -> {}
      },
    }
  end

  private

  def isolate_gems(gems)
    gems.each do |gem_name|
      if Gem.loaded_specs[gem_name]
          Gem.loaded_specs[gem_name].full_gem_path.tap do |path|
            $LOAD_PATH.reject! { |p| p.to_s.start_with?(path) }
          end
          Gem.loaded_specs.delete(gem_name)
      end
    end
  end

  def set_env()
    ENV['RAILS_ENV'] ||= 'development'
    log("using RAILS_ENV=#{ENV['RAILS_ENV']}")

    ENV['ROSI_PLATFORM'] ||= 'norwex'
    log("using ROSI_PLATFORM=#{ENV['ROSI_PLATFORM']}")
  end

  def git_dir(git_url)
    git_url.split("/").last.split(".").first
  end

  def log(msg)
    puts "=> #{msg}"
  end

  def default_isolated_gems
    ["timeout", "ffi", "json", "date", "bigdecimal", "mime-types", "mime-types-data"]
  end
end
