if Gem::Specification.all_names.any?{|g| g.start_with?("rosi")}
  require 'rosi'
end

# Load IRuby kernel patch early to ensure compatibility
begin
  require_relative 'rosi/lib/iruby/kernel_patch'
rescue LoadError
  # Skip if rosi is not available
end

