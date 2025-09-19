require 'tmpdir'
require 'fileutils'

module Rosi
  extend self

  def load(service, ref = nil)
    require_relative './iruby/ostream'

    unless services.include?(service)
      raise ArgumentError, "service #{service.inspect} not found, allowed services are: #{services.inspect}"
    end

    service_config = service_presets[service]
    temp_dir = Dir.mktmpdir("nj-")

    begin
      log("using temp dir #{temp_dir}")
      Dir.chdir(temp_dir) do
        $VERBOSE = nil
        
        log("cloning repo #{service_config[:git]}")
        clone_result = `git clone --depth 1 #{service_config[:git]} 2>&1`
        
        unless $?.success?
          raise "Failed to clone repository: #{clone_result}"
        end

        repo_dir = git_dir(service_config[:git])
        
        if ref
          log("using ref #{ref}")
          Dir.chdir(repo_dir) do
            fetch_result = `git fetch --depth=1 origin #{ref}:#{ref} 2>&1`
            checkout_result = `git checkout #{ref} 2>&1`
            
            unless $?.success?
              log("Warning: Could not checkout specific ref #{ref}, using default branch")
            end
          end
        else
          log("using default branch")
        end

        set_env

        root_path = File.join(temp_dir, repo_dir)
        
        if File.exist?(File.join(root_path, 'Gemfile'))
          log("running bundle install in #{root_path}")
          Dir.chdir(root_path) do
            # Ensure the service uses a compatible Ruby version
            tool_versions_file = '.tool-versions'
            container_ruby = RUBY_VERSION
            service_ruby = '3.3.4' # Services expect this version
            
            if File.exist?(tool_versions_file)
              content = File.read(tool_versions_file)
              # Keep service's expected Ruby version for compatibility
              new_content = content.gsub(/^ruby.*$/, "ruby #{service_ruby}")
              File.write(tool_versions_file, new_content)
              log("Service configured to use Ruby #{service_ruby}")
            else
              File.write(tool_versions_file, "ruby #{service_ruby}\n")
              log("Created .tool-versions with Ruby #{service_ruby}")
            end
            
            # Run bundle install with compatibility handling
            bundle_env = {
              'BUNDLE_GEMFILE' => File.join(root_path, 'Gemfile'),
              'BUNDLE_PATH' => File.join(root_path, 'vendor', 'bundle'),
              'RUBY_VERSION' => service_ruby
            }
            
            bundle_result = nil
            Dir.chdir(root_path) do
              # Try bundle install with various approaches
              bundle_commands = [
                "bundle install --quiet",
                "bundle install --deployment --quiet", 
                "RBENV_VERSION=#{container_ruby} bundle install --quiet"
              ]
              
              bundle_commands.each do |cmd|
                log("Attempting: #{cmd}")
                bundle_result = `#{cmd} 2>&1`
                if $?.success?
                  log("Bundle install successful")
                  break
                else
                  log("Command failed: #{bundle_result.strip}")
                end
              end
            end
            
            unless $?.success?
              log("All bundle install attempts failed")
              log("Final output: #{bundle_result}")
              # Don't raise error, just warn - some services might work without all gems
              log("Warning: Bundle install failed, some gems may be missing")
            end
          end
        else
          log("No Gemfile found, skipping bundle install")
        end

        log("cleaning up default gems")
        isolate_gems(service_config[:isolate_gems] || [])

        service_config[:before_load]&.call

        log("loading app")
        boot_file = File.join(root_path, 'config', 'boot.rb')
        app_file = File.join(root_path, 'config', 'application.rb')
        
        if File.exist?(boot_file)
          require boot_file
        else
          log("Warning: config/boot.rb not found")
        end
        
        if File.exist?(app_file)
          require app_file
        else
          log("Warning: config/application.rb not found")
        end

        Dir.chdir(root_path) do
          if defined?(Rails)
            Rails.application.require_environment!
          else
            log("Rails not detected, skipping environment initialization")
          end
        end
      end

      log("done")
      File.join(temp_dir, git_dir(service_config[:git]))
      
    rescue => e
      log("Error during service load: #{e.message}")
      FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
      raise e
    end
  end

  def configure_db(config)
    unless defined?(ActiveRecord)
      raise "ActiveRecord not available. Make sure a Rails service is loaded first."
    end

    current_config = ActiveRecord::Base.configurations[ENV['RAILS_ENV']] || {}
    new_config = current_config.merge(config)
    
    # Handle both Rails 6+ and older configuration formats
    if ActiveRecord::Base.respond_to?(:configurations=)
      # Rails 6+ style
      ActiveRecord::Base.configurations = ActiveRecord::DatabaseConfigurations.new(
        ENV['RAILS_ENV'] => new_config
      )
    end
    
    ActiveRecord::Base.establish_connection(new_config)
    log("Database configured successfully")
  rescue => e
    log("Error configuring database: #{e.message}")
    raise e
  end

  def services
    service_presets.keys
  end

  def service_presets
    @service_presets ||= {
      user: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_user_service.git",
        isolate_gems: default_isolated_gems,
        before_load: -> {}
      },
      catalog: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_catalog_service.git",
        isolate_gems: default_isolated_gems,
        before_load: -> {}
      },
      mybusiness: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_my_business_service.git",
        isolate_gems: default_isolated_gems,
        before_load: -> {}
      },
      cart: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_cart_service.git",
        isolate_gems: default_isolated_gems,
        before_load: -> {}
      },
      inventory: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_inventory_service.git",
        isolate_gems: default_isolated_gems,
        before_load: -> {}
      },
      oms: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_oms_service.git",
        isolate_gems: default_isolated_gems,
        before_load: -> {}
      },
      payment: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_payment_management_service.git",
        isolate_gems: default_isolated_gems,
        before_load: -> {}
      },
      rewards: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_rewards_service.git",
        isolate_gems: default_isolated_gems,
        before_load: -> {}
      },
      tax: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_tax_service.git",
        isolate_gems: default_isolated_gems,
        before_load: -> {}
      },
      virtual: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_virtual_fulfillment_service.git",
        isolate_gems: default_isolated_gems,
        before_load: -> {}
      },
      email: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_email_service.git",
        isolate_gems: default_isolated_gems,
        before_load: -> {}
      },
      ugc: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_ugc_service.git",
        isolate_gems: default_isolated_gems,
        before_load: -> {}
      },
      credits: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_credits_service.git",
        isolate_gems: default_isolated_gems,
        before_load: -> {}
      },
      subscription: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_subscription_service.git",
        isolate_gems: default_isolated_gems,
        before_load: -> {}
      },
      notification: {
        git: "git@gitlab.com:norwex/rosi/services/rosi_notification_service.git",
        isolate_gems: default_isolated_gems,
        before_load: -> {}
      }
    }.freeze
  end

  private

  def isolate_gems(gems)
    gems.each do |gem_name|
      loaded_spec = Gem.loaded_specs[gem_name]
      next unless loaded_spec

      gem_path = loaded_spec.full_gem_path
      
      # Remove from load path - use delete_if for Ruby 3.x compatibility
      $LOAD_PATH.delete_if { |path| path.to_s.start_with?(gem_path) }
      
      # Remove from loaded specs
      Gem.loaded_specs.delete(gem_name)
      
      # Also remove from required features if present
      gem_lib_paths = loaded_spec.require_paths.map { |p| File.join(gem_path, p) }
      $LOADED_FEATURES.delete_if do |feature|
        gem_lib_paths.any? { |lib_path| File.expand_path(feature).start_with?(lib_path) }
      end
      
      log("isolated gem: #{gem_name}")
    end
  rescue => e
    log("Warning: Error isolating gems - #{e.message}")
  end

  def set_env
    ENV['RAILS_ENV'] ||= 'development'
    log("using RAILS_ENV=#{ENV['RAILS_ENV']}")

    ENV['ROSI_PLATFORM'] ||= 'norwex'
    log("using ROSI_PLATFORM=#{ENV['ROSI_PLATFORM']}")
    
    # Set Ruby 3.3+ specific environment variables
    ENV['RUBY_YJIT_ENABLE'] ||= '1'
  end

  def git_dir(git_url)
    File.basename(git_url, '.git')
  end

  def log(msg)
    puts "=> #{msg}"
  end

  def default_isolated_gems
    [
      "timeout", 
      "ffi", 
      "json", 
      "date", 
      "bigdecimal", 
      "mime-types", 
      "mime-types-data",
      "net-protocol",  # Ruby 3+ standard library changes
      "net-http"       # Ruby 3+ standard library changes
    ].freeze
  end
end
