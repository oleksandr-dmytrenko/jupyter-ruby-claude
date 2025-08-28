# Compatibility patch for IRuby::Kernel initialization across IRuby/Ruby versions.
# In some IRuby releases, Kernel#initialize takes no args, while newer code paths
# may call it with positional/keyword arguments. This patch accepts any args and
# delegates to the original initializer when its arity is zero.

begin
  require 'iruby'
rescue LoadError
  # IRuby may be required later by the kernel launcher; if it's not available now,
  # we simply skip patching.
end

if defined?(::IRuby) && defined?(::IRuby::Kernel)
  IRuby::Kernel.class_eval do
    if instance_methods(false).include?(:initialize)
      original = instance_method(:initialize)
      # Only wrap if the original expects zero required args
      if original.arity == 0
        define_method(:initialize) do |*args, **kwargs, &blk|
          # Ignore any incoming args/kwargs to maintain backward compat
          original.bind_call(self, &blk)
        end
      end
    end
  end
end
