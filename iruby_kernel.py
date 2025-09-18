#!/usr/bin/env python3
"""
Python-based IRuby kernel that maintains a persistent Ruby session.
This replaces the problematic IRuby kernel with a proper Python solution.
"""

import subprocess
import sys
import json
import os
import tempfile
import threading
import time
import queue
from ipykernel.kernelbase import Kernel

class IRubyKernel(Kernel):
    implementation = 'IRuby'
    implementation_version = '1.0'
    language = 'ruby'
    language_version = '3.3.4'
    language_info = {
        'name': 'ruby',
        'mimetype': 'text/x-ruby',
        'file_extension': '.rb',
        'pygments_lexer': 'ruby',
        'version': '3.3.4'
    }
    banner = "IRuby 3.3.4 Kernel"

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.ruby_path = '/root/.asdf/shims/ruby'
        self.working_dir = '/nori-jupyter'
        self.lock = threading.Lock()
        self.ruby_process = None
        self.output_queue = queue.Queue()
        self.start_ruby_session()
    
    def start_ruby_session(self):
        """Start a persistent Ruby process for the session"""
        try:
            # Create a Ruby script that maintains state
            self.ruby_script = os.path.join(self.working_dir, 'iruby_session.rb')
            with open(self.ruby_script, 'w') as f:
                f.write("""#!/usr/bin/env ruby
# IRuby session script - optimized for performance

# Enable immediate output flushing
$stdout.sync = true
$stderr.sync = true

# Create a binding to maintain variable scope
$binding = binding

# Override puts to capture output - optimized
def puts(*args)
  if args.empty?
    STDOUT.puts
  else
    args.each { |arg| STDOUT.puts(arg) }
  end
  STDOUT.flush
end

# Override print to capture output - optimized
def print(*args)
  args.each { |arg| STDOUT.print(arg) }
  STDOUT.flush
end

# Override p to capture output - optimized
def p(*args)
  args.each { |arg| STDOUT.puts(arg.inspect) }
  STDOUT.flush
end

# Main execution loop - optimized
loop do
  begin
    line = STDIN.gets
    break if line.nil?
    
    code = line.strip
    next if code.empty?
    
    # Execute the code in the persistent binding
    result = eval(code, $binding)
    
    # Print result if it's not nil and not already printed
    # Skip IO objects and other internal objects - optimized check
    if !result.nil? && !result.is_a?(IO) && !result.is_a?(Binding) && result != $stdout && result != $stderr
      puts result.inspect
      STDOUT.flush
    end
  rescue => e
    puts "ERROR: #{e.class.name}: #{e.message}"
    if e.backtrace
      e.backtrace.each { |line| puts "  #{line}" }
    end
  end
end
""")
            
            # Start Ruby process
            self.ruby_process = subprocess.Popen(
                [self.ruby_path, self.ruby_script],
                cwd=self.working_dir,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=0
            )
            
            # Start output reader thread
            self.output_thread = threading.Thread(target=self._read_output)
            self.output_thread.daemon = True
            self.output_thread.start()
            
        except Exception as e:
            print(f"Failed to start Ruby session: {e}")
            self.ruby_process = None
    
    def _read_output(self):
        """Read output from Ruby process in a separate thread - optimized for speed"""
        while self.ruby_process and self.ruby_process.poll() is None:
            try:
                line = self.ruby_process.stdout.readline()
                if line:
                    self.output_queue.put(('stdout', line.rstrip()))
                else:
                    # Reduced sleep time for faster response
                    time.sleep(0.001)
            except:
                break
    
    def do_execute(self, code, silent, store_history=True, user_expressions=None, allow_stdin=False):
        if not code.strip():
            return {'status': 'ok', 'execution_count': self.execution_count,
                    'payload': [], 'user_expressions': {}}

        with self.lock:
            try:
                if not self.ruby_process or self.ruby_process.poll() is not None:
                    self.start_ruby_session()
                    if not self.ruby_process:
                        return {'status': 'error', 'execution_count': self.execution_count,
                                'ename': 'RubyError', 'evalue': 'Failed to start Ruby session',
                                'traceback': []}
                
                # Clear output queue
                while not self.output_queue.empty():
                    self.output_queue.get()
                
                # Send code to Ruby process
                self.ruby_process.stdin.write(code + "\n")
                self.ruby_process.stdin.flush()
                
                # Stream output in real-time for long-running operations
                output_lines = []
                error_lines = []
                start_time = time.time()
                last_output_time = start_time
                
                
                while time.time() - start_time < 300:  # 5 minute timeout for very long operations
                    try:
                        output_type, line = self.output_queue.get(timeout=0.1)  # Slightly longer timeout
                        if output_type == 'stdout':
                            if line.startswith('ERROR:'):
                                error_lines.append(line[6:])  # Remove 'ERROR: ' prefix
                                # Send error immediately
                                self.send_response(self.iopub_socket, 'stream', {
                                    'name': 'stderr',
                                    'text': line[6:]
                                })
                            else:
                                output_lines.append(line)
                                # Send output immediately for real-time streaming with proper formatting
                                # Ensure each line is properly separated
                                formatted_line = line if line.endswith('\n') else line + '\n'
                                self.send_response(self.iopub_socket, 'stream', {
                                    'name': 'stdout',
                                    'text': formatted_line
                                })
                            last_output_time = time.time()
                    except queue.Empty:
                        # Check if process is still alive
                        if self.ruby_process.poll() is not None:
                            break
                        # For short operations, wait a bit longer to ensure we capture all output
                        # For long operations like Rosi.load, continue waiting much longer
                        if not output_lines and not error_lines:
                            # No output yet, continue waiting
                            continue
                        elif 'Rosi.load' in code or 'bundle install' in '\n'.join(output_lines):
                            # For Rosi.load operations, wait up to 30 seconds for more output
                            if time.time() - last_output_time > 30.0:
                                break
                        elif time.time() - last_output_time > 0.5:  # Wait 500ms after last output for short operations
                            break
                        continue
                    except Exception as e:
                        # Debug: Send error message
                        self.send_response(self.iopub_socket, 'stream', {
                            'name': 'stderr',
                            'text': f'[DEBUG] Exception in output collection: {str(e)}'
                        })
                        break
                
                
                # Send completion message for long-running operations
                if 'Rosi.load' in code or len(output_lines) > 10:
                    self.send_response(self.iopub_socket, 'stream', {
                        'name': 'stdout',
                        'text': '\n✅ Done\n'
                    })
                
                # Return execution result
                if error_lines:
                    return {'status': 'error', 'execution_count': self.execution_count,
                            'ename': 'RubyError', 'evalue': error_lines[0],
                            'traceback': error_lines}
                else:
                    return {'status': 'ok', 'execution_count': self.execution_count,
                            'payload': [], 'user_expressions': {}}
                    
            except Exception as e:
                return {'status': 'error', 'execution_count': self.execution_count,
                        'ename': 'KernelError', 'evalue': str(e),
                        'traceback': []}

if __name__ == '__main__':
    from ipykernel.kernelapp import IPKernelApp
    IPKernelApp.launch_instance(kernel_class=IRubyKernel)
