require_relative './iruby/kernel_patch'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'

module Rosi
  extend self

  def load(service, ref = nil)
    require_relative './iruby/ostream'

    validate_service!(service)
    service_config = service_presets[service]

    Dir.mktmpdir("nj-") do |dir|
      $VERBOSE = nil
      root_path = local_or_cloned_service_path(service_config, ref, dir)
      setup_env(root_path)
      install_gems(root_path)
      isolate_environment
      run_before_load(service_config)
      load_rails_app(root_path)
      log("done")
      root_path
    end
  end

  def configure_db(config)
    env_config = ActiveRecord::Base.configurations[ENV['RAILS_ENV']]
    ActiveRecord::Base.establish_connection(env_config.merge(config))
  end

  def services
    service_presets.keys
  end

  def service_presets
    @service_presets ||= %i[
      user catalog mybusiness cart inventory oms payment rewards tax virtual
      email ugc credits subscription notification
    ].map { |name|
      [name, {
        git: "git@gitlab.com:norwex/rosi/services/rosi_#{name}_service.git",
        isolate_gems: [],
        before_load: -> {}
      }]
    }.to_h
  end

  private

  def validate_service!(service)
    return if services.include?(service)
    raise "service #{service.inspect} not found, allowed services are: #{services.inspect}"
  end

  def local_or_cloned_service_path(service_config, ref, temp_dir)
    local_path = ENV['ROSI_SERVICE_PATH']
    if local_path&.strip&.present?
      log("using local service path #{local_path}")
      local_path
    else
      clone_and_checkout(service_config[:git], ref, temp_dir)
    end
  end

  def clone_and_checkout(git_url, ref, temp_dir)
    repo_dir = File.join(temp_dir, git_dir(git_url))

    if Dir.exist?(repo_dir)
      log("removing existing repo dir #{repo_dir}")
      FileUtils.rm_rf(repo_dir)
    end

    log("cloning repo #{git_url}")
    clone_out = `git clone --depth 1 #{git_url} #{repo_dir} 2>&1`
    raise "git clone failed: #{clone_out}" unless $?.success?

    Dir.chdir(repo_dir) { checkout_ref(ref) } if ref
    repo_dir
  end

  def checkout_ref(ref)
    log("using ref #{ref}")
    %W[fetch checkout].each do |cmd|
      output = case cmd
               when 'fetch' then `git fetch --depth=1 origin #{ref}:#{ref} 2>&1`
               when 'checkout' then `git checkout #{ref} 2>&1`
               end
      raise "git #{cmd} failed: #{output}" unless $?.success?
    end
  end

  def setup_env(root_path)
    ENV['RAILS_ENV'] ||= 'development'
    log("using RAILS_ENV=#{ENV['RAILS_ENV']}")

    ENV['ROSI_PLATFORM'] ||= 'norwex'
    log("using ROSI_PLATFORM=#{ENV['ROSI_PLATFORM']}")

    bundle_dir = default_bundle_dir
    FileUtils.mkdir_p(bundle_dir)

    ruby_ver = RbConfig::CONFIG['ruby_version']
    ENV['BUNDLE_SILENCE_ROOT_WARNING'] = '1'
    ENV['BUNDLE_PATH'] = bundle_dir
    ENV['GEM_HOME'] = File.join(bundle_dir, 'ruby', ruby_ver)
    ENV['GEM_PATH'] = bundle_dir
    ENV['BUNDLE_GEMFILE'] = File.join(root_path, 'Gemfile')
  end

  def install_gems(root_path)
    log("running bundle install in #{root_path}")
    require 'bundler'
    Bundler.with_unbundled_env do
      Dir.chdir(root_path) { raise 'bundle install failed' unless system("bundle install --path #{ENV['BUNDLE_PATH']}") }
    end
  end

  def run_before_load(service_config)
    service_config[:before_load]&.call
    Bundler.reset!
    Bundler.setup
    log_env_info
  end

  def log_env_info
    bundler_version = defined?(Bundler) && Bundler.const_defined?(:VERSION) ? Bundler::VERSION : 'unknown'
    log("env: Ruby #{RUBY_VERSION} (#{RUBY_PLATFORM}), Bundler #{bundler_version}, Gemfile=#{ENV['BUNDLE_GEMFILE']}")
  end

  def load_rails_app(root_path)
    log("loading app")
    require File.join(root_path, 'config', 'boot')
    require File.join(root_path, 'config', 'application')
    Dir.chdir(root_path) { Rails.application.require_environment! }
  end

  # --- Gem isolation ---
  def default_bundle_dir
    base = ENV['ROSI_BUNDLE_BASE'] || File.join(Dir.tmpdir, 'iruby-bundles')
    File.join(base, "pid-#{Process.pid}")
  end

  def isolate_environment(keep = %w[bundler iruby rosi])
    (Gem.loaded_specs.keys - keep).each do |gem_name|
      path = Gem.loaded_specs[gem_name].full_gem_path
      $LOAD_PATH.reject! { |p| p.start_with?(path) }
      Gem.loaded_specs.delete(gem_name)
    end
    require 'bundler'
    Bundler.reset!
  end

  def git_dir(git_url)
    git_url.split("/").last.split(".").first
  end

  def log(msg)
    puts "=> #{msg}"
  end
end
