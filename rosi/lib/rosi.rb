module Rosi
  extend self

  def load(service, ref = nil)
    require_relative './iruby/ostream'
    require_relative './iruby/kernel_patch'
    
    # Ensure Zeitwerk is available
    begin
      require 'zeitwerk'
    rescue LoadError
      raise "The 'zeitwerk' gem is required. Please add it to your environment's Gemfile."
    end
  
    if not services().include?(service)
      raise "service #{service.inspect} not found, allowed services are: #{services().inspect}"
    end
  
    service = service_presets()[service]
    dir = Dir.mktmpdir("nj-")
  
    log("using temp dir #{dir}")
  
    result_path = Dir.chdir(dir) do
      $VERBOSE = nil
      log("cloning repo #{service[:git]}")
      require 'open3'
      Open3.popen2e("git clone --depth 1 #{service[:git]}") do |_stdin, stdout_err, wait_thr|
        stdout_err.each { |line| puts line; $stdout.flush }
        puts "git clone finished with status #{wait_thr.value.exitstatus}"
        $stdout.flush
      end
  
      if ref
        log("using ref #{ref}")
        Dir.chdir(git_dir(service[:git])) do
          Open3.popen2e("git fetch --depth=1 origin #{ref}:#{ref}") do |_stdin, stdout_err, wait_thr|
            stdout_err.each { |line| puts line; $stdout.flush }
            puts "git fetch finished with status #{wait_thr.value.exitstatus}"
            $stdout.flush
          end
          Open3.popen2e("git checkout #{ref}") do |_stdin, stdout_err, wait_thr|
            stdout_err.each { |line| puts line; $stdout.flush }
            puts "git checkout finished with status #{wait_thr.value.exitstatus}"
            $stdout.flush
          end
        end
      else
        log("using ref main")
      end
  
      set_env()
  
      root_path = "#{Dir.pwd}/#{git_dir(service[:git])}"
      log("running bundle install in #{root_path}")
      Dir.chdir(root_path) do
        require 'open3'
        
        # Temporarily disable asdf Ruby plugin to prevent asdf command execution
        asdf_plugin_path = "#{ENV['ASDF_DIR']}/plugins/ruby/rubygems-plugin"
        plugin_backup_path = "#{asdf_plugin_path}.disabled"
        
        begin
          # Disable the asdf Ruby plugin temporarily
          if Dir.exist?(asdf_plugin_path) && !Dir.exist?(plugin_backup_path)
            log("temporarily disabling asdf Ruby plugin...")
            # Use copy and remove instead of rename to avoid cross-device link issues
            require 'fileutils'
            FileUtils.cp_r(asdf_plugin_path, plugin_backup_path)
            FileUtils.rm_rf(asdf_plugin_path)
          end
          
          # Set up environment for bundle commands
          bundle_env = {
            'PATH' => ENV['PATH'],
            'GEM_HOME' => ENV['GEM_HOME'],
            'GEM_PATH' => ENV['GEM_PATH'],
            'BUNDLE_GEMFILE' => '',
            'ASDF_DIR' => ENV['ASDF_DIR'],
            'ASDF_DATA_DIR' => ENV['ASDF_DATA_DIR']
          }
          
          log("cleaning bundle cache...")
          Open3.popen2e(bundle_env, 'bundle clean --force') do |_stdin, stdout_err, _wait_thr|
            stdout_err.each { |line| puts "    #{line}"; $stdout.flush }
          end
          
          File.delete('Gemfile.lock') if File.exist?('Gemfile.lock')
          
          log("running bundle install with asdf Ruby plugin disabled...")
          Open3.popen2e(bundle_env, 'bundle install') do |_stdin, stdout_err, wait_thr|
            stdout_err.each { |line| puts line; $stdout.flush }
            puts "bundle install finished with status #{wait_thr.value.exitstatus}"
            $stdout.flush
          end
        ensure
          # Re-enable the asdf Ruby plugin
          if Dir.exist?(plugin_backup_path) && !Dir.exist?(asdf_plugin_path)
            log("re-enabling asdf Ruby plugin...")
            # Use copy and remove instead of rename to avoid cross-device link issues
            FileUtils.cp_r(plugin_backup_path, asdf_plugin_path)
            FileUtils.rm_rf(plugin_backup_path)
          end
        end
      end
  
      log("cleaning up default gems")
      isolate_gems(service[:isolate_gems] || [])
  
      service[:before_load].call if service[:before_load]
  
      log("loading app")
      require_relative "#{root_path}/config/boot"
      require_relative "#{root_path}/config/application"
  
      Dir.chdir(root_path) do
        Rails.application.require_environment!

        # Ensure the entire Rails context (all classes) is loaded and available
        log("Eager loading Rails application classes...")
        Rails.application.eager_load!
        if defined?(Zeitwerk::Loader)
          Zeitwerk::Loader.eager_load_all
        end
        log("Eager loading complete. Service constants are now available.")
      end
  
      "#{dir}/#{git_dir(service[:git])}"
    end
  
    log("done")
    log("Rosi.load completed successfully. Service loaded at: #{result_path}")
    result_path
  end
  
  def configure_db(config)
    # Ensure ActiveRecord is loaded (required for Ruby 3.3.4 compatibility)
    require 'active_record' unless defined?(ActiveRecord)
    
    log("Configuring database connection...")
    
    # Validate input configuration
    unless config.is_a?(Hash)
      raise ArgumentError, "Configuration must be a Hash, got #{config.class}"
    end
    
    # Normalize keys to symbols (deep) before any processing
    normalized_input = symbolize_keys_deep(config)
    
    # Resolve dynamic host if provided
    resolved_config = resolve_database_config(normalized_input)
    
    # Get base configuration for the current Rails environment
    base_config = {}
    if defined?(ActiveRecord::Base) && ActiveRecord::Base.configurations
      configs = ActiveRecord::Base.configurations
      if configs.respond_to?(:configs_for)
        found = configs.configs_for(env_name: ENV['RAILS_ENV'])
        # AR >= 6 returns an array; take first matching config
        if found.respond_to?(:first)
          item = found.first
          base_config = item ? (item.respond_to?(:configuration_hash) ? item.configuration_hash : item) : {}
        end
      elsif configs.respond_to?(:[])
        base_config = configs[ENV['RAILS_ENV']] || {}
      end
    end

    # Normalize keys to symbols for predictable merging
    if base_config.is_a?(Hash)
      sym_base = {}
      base_config.each { |k, v| sym_base[k.to_sym] = v }
      base_config = sym_base
    end
    
    # Merge configurations
    new_config = base_config.merge(resolved_config)
    
    # Validate required configuration keys
    required_keys = [:adapter, :host, :database]
    missing_keys = required_keys - new_config.keys
    if missing_keys.any?
      raise ArgumentError, "Missing required configuration keys: #{missing_keys.join(', ')}"
    end
    
    # Prepare host fallbacks with more comprehensive options
    host_candidates = [new_config[:host]].compact.uniq
    if new_config[:host].is_a?(String)
      host = new_config[:host]
      if host =~ /^db\.(.+)\.dyn\.norwex\.com$/
        env_id = Regexp.last_match(1)
        host_candidates |= ["my.#{env_id}.dyn.norwex.com", "db.#{env_id}.norwex.com", "my.#{env_id}.norwex.com"]
      elsif host =~ /^my\.(.+)\.dyn\.norwex\.com$/
        env_id = Regexp.last_match(1)
        host_candidates |= ["db.#{env_id}.dyn.norwex.com", "db.#{env_id}.norwex.com", "my.#{env_id}.norwex.com"]
      elsif host =~ /^db\.(.+)\.norwex\.com$/
        env_id = Regexp.last_match(1)
        host_candidates |= ["my.#{env_id}.norwex.com", "db.#{env_id}.dyn.norwex.com", "my.#{env_id}.dyn.norwex.com"]
      elsif host =~ /^my\.(.+)\.norwex\.com$/
        env_id = Regexp.last_match(1)
        host_candidates |= ["db.#{env_id}.norwex.com", "db.#{env_id}.dyn.norwex.com", "my.#{env_id}.dyn.norwex.com"]
      end
    end

    last_error = nil
    connection_established = false
    
    host_candidates.each do |host|
      attempt_config = new_config.merge(host: host)
      log("Attempting database connection to #{attempt_config[:host]}:#{attempt_config[:port] || 3306}/#{attempt_config[:database]}")
      
      begin
        # Clear any existing connection first
        ActiveRecord::Base.remove_connection if ActiveRecord::Base.connected?
        
        # Establish new connection
        ActiveRecord::Base.establish_connection(attempt_config)
        
        # Force a real connection test
        conn = ActiveRecord::Base.connection
        conn.execute("SELECT 1") # This will actually hit the database
        
        if conn.active?
          log("Successfully connected to #{attempt_config[:host]}")
          connection_established = true
          return ActiveRecord::Base.connection_pool
        end
      rescue => e
        last_error = e
        log("Connection attempt failed for #{attempt_config[:host]}: #{e.class}: #{e.message}")
        next
      end
    end

    # Provide helpful error message if all attempts failed
    error_msg = "Failed to establish ActiveRecord connection after trying #{host_candidates.size} host(s): #{host_candidates.join(', ')}"
    if last_error
      error_msg += "\nLast error: #{last_error.class}: #{last_error.message}"
      if last_error.message.include?("Unknown server host") || last_error.message.include?("Can't connect to server")
        error_msg += "\n\nNote: Database hosts may require VPN/tunnel connection. Please ensure you're connected to the appropriate network."
      end
    end
    
    raise error_msg
  end

  def services()
    service_presets().keys
  end

  # Helper method to test if a class is available (useful for debugging)
  def class_available?(class_name)
    begin
      Object.const_get(class_name)
      true
    rescue NameError
      false
    end
  end

  # Helper method to list available model classes
  def available_models
    return [] unless defined?(Rails) && Rails.application
    
    models = []
    model_dirs = [
      Rails.root.join('app/models'),
      Rails.root.join('app/services'),
      Rails.root.join('lib')
    ].select { |dir| Dir.exist?(dir) }
    
    model_dirs.each do |dir|
      Dir.glob("#{dir}/**/*.rb").each do |file|
        relative_path = file.sub("#{dir}/", '').sub('.rb', '')
        class_name = relative_path.split('/').map(&:camelize).join('::')
        models << class_name
      end
    end
    
    models.uniq.sort
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

  def symbolize_keys_deep(object)
    case object
    when Hash
      object.each_with_object({}) do |(key, value), memo|
        sym_key = key.respond_to?(:to_sym) ? key.to_sym : key
        memo[sym_key] = symbolize_keys_deep(value)
      end
    when Array
      object.map { |item| symbolize_keys_deep(item) }
    else
      object
    end
  end

  def resolve_database_config(config)
    resolved_config = config.dup
    host = resolved_config[:host]&.to_s
    
    if host && !host.empty?
      # Leave IPs and URLs untouched
      is_ip = host =~ /\A\d{1,3}(?:\.\d{1,3}){3}\z/
      is_url = host.include?('://')
      unless is_ip || is_url
        # Already a full dyn FQDN? keep as is
        if host =~ /\A(?:db|my)\.[^.]+\.dyn\.norwex\.com\z/
          # no-op
        # Form: db.noki-1862 → append dyn domain
        elsif host =~ /\A(?:db|my)\.[^.]+\z/
          resolved_config[:host] = "#{host}.dyn.norwex.com"
          log("Resolved short host: #{host} → #{resolved_config[:host]}")
        # Form: noki-1862 → prefix with db. and append domain
        elsif host !~ /\./
          resolved_config[:host] = "db.#{host}.dyn.norwex.com"
          log("Resolved env id: #{host} → #{resolved_config[:host]}")
        else
          # Some other domain, keep as is
        end
        # Default MySQL port if host provided
        resolved_config[:port] ||= 3306
      end
    end
    
    # Ensure adapter is set for all configurations
    resolved_config[:adapter] ||= 'mysql2'
    
    resolved_config
  end

  def load_service_classes
    # Ensure Rails is loaded
    return unless defined?(Rails) && Rails.application
    
    log("Loading service classes for lazy loading...")
    
    # Get all autoload paths from Rails
    autoload_paths = Rails.application.config.autoload_paths + Rails.application.config.eager_load_paths
    
    # Create a Zeitwerk loader for service classes
    service_loader = Zeitwerk::Loader.new
    
    # Add all Rails autoload paths to the service loader
    autoload_paths.uniq.each do |path|
      if Dir.exist?(path)
        service_loader.push_dir(path)
        log("Added autoload path: #{path}")
      end
    end
    
    # Preload common model directories to ensure they're available
    model_dirs = [
      Rails.root.join('app/models'),
      Rails.root.join('app/services'),
      Rails.root.join('lib')
    ].select { |dir| Dir.exist?(dir) }
    
    model_dirs.each do |dir|
      service_loader.push_dir(dir)
      log("Added model directory: #{dir}")
    end
    
    # Set up the loader for lazy loading
    service_loader.setup
    
    # Enable reloading for development
    if Rails.env.development?
      service_loader.enable_reloading
    end
    
    # Set up autoloading for common model patterns
    setup_autoloading_patterns(service_loader)
    
    log("Service classes loaded. Zeitwerk loader configured with #{service_loader.dirs.size} directories.")
    
    # Return the loader for potential future use
    service_loader
  end

  def setup_autoloading_patterns(loader)
    # Set up custom autoloading patterns for common service patterns
    loader.inflector.inflect(
      'api' => 'API',
      'http' => 'HTTP',
      'json' => 'JSON',
      'xml' => 'XML',
      'csv' => 'CSV',
      'pdf' => 'PDF',
      'url' => 'URL',
      'uri' => 'URI',
      'id' => 'ID',
      'uuid' => 'UUID'
    )
    
    # Set up custom namespace patterns
    loader.inflector.inflect(
      'rosi_user_service' => 'RosiUserService',
      'rosi_catalog_service' => 'RosiCatalogService',
      'rosi_my_business_service' => 'RosiMyBusinessService',
      'rosi_cart_service' => 'RosiCartService',
      'rosi_inventory_service' => 'RosiInventoryService',
      'rosi_oms_service' => 'RosiOmsService',
      'rosi_payment_management_service' => 'RosiPaymentManagementService',
      'rosi_rewards_service' => 'RosiRewardsService',
      'rosi_tax_service' => 'RosiTaxService',
      'rosi_virtual_fulfillment_service' => 'RosiVirtualFulfillmentService',
      'rosi_email_service' => 'RosiEmailService',
      'rosi_ugc_service' => 'RosiUgcService',
      'rosi_credits_service' => 'RosiCreditsService',
      'rosi_subscription_service' => 'RosiSubscriptionService',
      'rosi_notification_service' => 'RosiNotificationService'
    )
  end

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
    timestamp = Time.now.strftime("%H:%M:%S")
    puts "[#{timestamp}] => #{msg}"
    $stdout.flush
  end

  def default_isolated_gems
    ["timeout", "ffi", "json", "date", "bigdecimal", "mime-types", "mime-types-data"]
  end
end
