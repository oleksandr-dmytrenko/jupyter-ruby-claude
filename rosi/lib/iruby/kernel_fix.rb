# IRuby Kernel Initialization and Output Fix for Ruby 3.3.4
# This file should be saved as: rosi/lib/iruby/kernel_fix.rb

# Ensure proper IRuby initialization
require 'json'
require 'securerandom'

module IRuby
  # Fix for Ruby 3.3+ compatibility in kernel execution
  module KernelFix
    def self.included(base)
      base.class_eval do
        # Override execute to ensure proper output capture
        def execute(code, store_history: true, silent: false, allow_stdin: true)
          # Ensure stdout/stderr are properly set up
          original_stdout = $stdout
          original_stderr = $stderr
          
          begin
            # Force output synchronization
            $stdout.sync = true if $stdout.respond_to?(:sync=)
            $stderr.sync = true if $stderr.respond_to?(:sync=)
            
            # Execute the code
            result = nil
            exception = nil
            
            begin
              # Capture the result properly
              result = eval(code, TOPLEVEL_BINDING)
            rescue SystemExit => e
              exception = e
            rescue => e
              exception = e
            end
            
            # Handle the result
            unless silent
              if exception
                # Send error back to Jupyter
                send_error(exception)
              elsif result && !result.nil?
                # Send result back to Jupyter  
                send_execute_result(result)
              end
            end
            
            # Return execution status
            {
              status: exception ? 'error' : 'ok',
              execution_count: @execution_count,
              result: result,
              exception: exception
            }
            
          ensure
            # Restore original streams
            $stdout = original_stdout
            $stderr = original_stderr
          end
        end
        
        private
        
        def send_execute_result(result)
          # Format result for Jupyter display
          content = {
            execution_count: @execution_count,
            data: format_result(result),
            metadata: {}
          }
          
          send_message(:execute_result, content) if respond_to?(:send_message)
        end
        
        def send_error(exception)
          # Format error for Jupyter display
          content = {
            ename: exception.class.name,
            evalue: exception.message,
            traceback: exception.backtrace || []
          }
          
          send_message(:error, content) if respond_to?(:send_message)
        end
        
        def format_result(result)
          # Convert result to displayable format
          case result
          when String
            { 'text/plain' => result.inspect }
          when Numeric, TrueClass, FalseClass, NilClass
            { 'text/plain' => result.inspect }
          when Array, Hash
            { 'text/plain' => result.inspect }
          else
            if result.respond_to?(:to_s)
              { 'text/plain' => result.to_s }
            else
              { 'text/plain' => result.inspect }
            end
          end
        end
      end
    end
  end
end

# Apply the fix if IRuby::Kernel exists
if defined?(IRuby::Kernel)
  IRuby::Kernel.include(IRuby::KernelFix)
end

# Additional compatibility patches
module IRuby
  # Ensure Display module works correctly
  module Display
    def self.display(object, **options)
      # Handle display with proper Ruby 3.3+ compatibility
      if object.respond_to?(:to_iruby)
        object.to_iruby
      else
        { 'text/plain' => object.inspect }
      end
    end
  end
  
  # Fix for potential ZMQ issues in Ruby 3.3+
  if defined?(ZMQ)
    module ZMQFix
      def self.ensure_context
        # Ensure ZMQ context is properly initialized
        @context ||= ZMQ::Context.new
      end
    end
  end
end
