# Minimal IRuby OStream Fix for Ruby 3.3.4 Output Issues
module IRuby
  class OStream
    def closed?
      false
    end
    
    def close
      nil
    end
    
    def external_encoding
      Encoding::UTF_8
    end
    
    def internal_encoding
      nil
    end
    
    def sync
      true
    end
    
    def sync=(val)
      true
    end
  end
end

# Force proper output handling in IRuby
if defined?(IRuby::Kernel)
  module IRuby
    class Kernel
      # Override execute_request to ensure output is captured and sent
      alias_method :original_execute_request, :execute_request if method_defined?(:execute_request)
      
      def execute_request(msg)
        # Store original streams
        orig_stdout = $stdout
        orig_stderr = $stderr
        
        # Capture output
        require 'stringio'
        stdout_capture = StringIO.new
        stderr_capture = StringIO.new
        
        begin
          # Redirect streams but keep them teed to original
          $stdout = MultiIO.new(orig_stdout, stdout_capture)
          $stderr = MultiIO.new(orig_stderr, stderr_capture)
          
          # Execute the original request
          result = if respond_to?(:original_execute_request)
            original_execute_request(msg)
          else
            super(msg)
          end
          
          # Send any captured output as stream messages
          stdout_content = stdout_capture.string
          stderr_content = stderr_capture.string
          
          if !stdout_content.empty?
            send_stream('stdout', stdout_content)
          end
          
          if !stderr_content.empty?
            send_stream('stderr', stderr_content)
          end
          
          result
        ensure
          # Restore streams
          $stdout = orig_stdout  
          $stderr = orig_stderr
        end
      end
      
      private
      
      def send_stream(name, text)
        content = {
          name: name,
          text: text
        }
        send_message(:stream, content) if respond_to?(:send_message)
      end
    end
  end
  
  # Helper class to duplicate output to multiple streams
  class MultiIO
    def initialize(*streams)
      @streams = streams
    end
    
    def write(str)
      @streams.each { |stream| stream.write(str) }
    end
    
    def puts(*args)
      @streams.each { |stream| stream.puts(*args) }
    end
    
    def print(*args)
      @streams.each { |stream| stream.print(*args) }
    end
    
    def printf(*args)
      @streams.each { |stream| stream.printf(*args) }
    end
    
    def flush
      @streams.each { |stream| stream.flush if stream.respond_to?(:flush) }
    end
    
    def sync=(val)
      @streams.each { |stream| stream.sync = val if stream.respond_to?(:sync=) }
    end
    
    def sync
      true
    end
    
    def close
      # Don't close original streams
    end
    
    def closed?
      false
    end
  end
end
