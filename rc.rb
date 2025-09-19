# Minimal rc.rb focused on fixing IRuby output for Ruby 3.3.4
puts "=> Initializing Ruby #{RUBY_VERSION} environment..."

# Load rosi if available
begin
  if Gem::Specification.find_all_by_name('rosi').any?
    require 'rosi'
    puts "=> Rosi gem loaded successfully"
  end
rescue => e
  puts "=> Warning: Could not load rosi gem - #{e.message}"
end

# Critical IRuby output fixes for Ruby 3.3.0
if defined?(IRuby)
  puts "=> Applying IRuby output fixes..."
  
  # Force output to be immediately visible
  $stdout.sync = true if $stdout.respond_to?(:sync=)
  $stderr.sync = true if $stderr.respond_to?(:sync=)
  
  # Set proper encoding
  if $stdout.respond_to?(:set_encoding)
    $stdout.set_encoding(Encoding::UTF_8)
    $stderr.set_encoding(Encoding::UTF_8)
  end
  
  puts "=> IRuby output fixes applied"
end

# Ruby 3.3+ optimizations
if RUBY_VERSION >= '3.3.0'
  # Enable YJIT if available
  if defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enable) && !RubyVM::YJIT.enabled?
    begin
      RubyVM::YJIT.enable
      puts "=> YJIT enabled"
    rescue => e
      puts "=> YJIT not available: #{e.message}"
    end
  end
  
  # Set encoding defaults
  Encoding.default_external = Encoding::UTF_8
  Encoding.default_internal = Encoding::UTF_8
end

puts "=> Ruby environment initialized"
