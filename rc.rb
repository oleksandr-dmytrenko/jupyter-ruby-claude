# Ensure IRuby is loaded early so compatibility patches can apply
begin
  require 'iruby'
rescue LoadError
  # IRuby may not be available in non-kernel processes; ignore
end

if Gem::Specification.all_names.any?{|g| g.start_with?("rosi")}
  require 'rosi'
end

