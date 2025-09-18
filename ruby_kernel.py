#!/usr/bin/env python3
"""
Custom Ruby kernel for Jupyter that properly executes Ruby code.
This replaces the problematic IRuby kernel with a Python-based solution.
"""

import subprocess
import sys
import json
import os
import tempfile
import threading
from ipykernel.kernelbase import Kernel

class RubyKernel(Kernel):
    implementation = 'Ruby'
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
    banner = "Ruby 3.3.4 Kernel"

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.ruby_path = '/root/.asdf/shims/ruby'
        self.working_dir = '/nori-jupyter'
        self.session_file = os.path.join(self.working_dir, '.ruby_session.rb')
        self.lock = threading.Lock()
        
        # Initialize session file
        with open(self.session_file, 'w') as f:
            f.write("# Ruby session file\n")

    def do_execute(self, code, silent, store_history=True, user_expressions=None, allow_stdin=False):
        if not code.strip():
            return {'status': 'ok', 'execution_count': self.execution_count,
                    'payload': [], 'user_expressions': {}}

        with self.lock:
            try:
                # Append code to session file
                with open(self.session_file, 'a') as f:
                    f.write(f"\n# Cell {self.execution_count}\n")
                    f.write(code)
                    f.write("\n")
                
                # Create a Ruby script that loads the session and executes the new code
                ruby_script = f"""
# Load the session file to get all previous variables
load '{self.session_file}'

# Execute the new code and capture result
begin
  result = begin
    {code}
  end
  
  # If result is not nil and not already printed, print it
  if !result.nil? && result != :__no_output__
    puts result.inspect
  end
rescue => e
  puts e.class.name + ': ' + e.message
  puts e.backtrace.join("\\n") if e.backtrace
  exit 1
end
"""
                
                # Execute Ruby script
                result = subprocess.run(
                    [self.ruby_path, '-e', ruby_script],
                    cwd=self.working_dir,
                    capture_output=True,
                    text=True,
                    timeout=30
                )
                
                # Send output to Jupyter
                if result.stdout:
                    self.send_response(self.iopub_socket, 'stream', {
                        'name': 'stdout',
                        'text': result.stdout
                    })
                
                if result.stderr:
                    self.send_response(self.iopub_socket, 'stream', {
                        'name': 'stderr', 
                        'text': result.stderr
                    })
                
                # Return execution result
                if result.returncode == 0:
                    return {'status': 'ok', 'execution_count': self.execution_count,
                            'payload': [], 'user_expressions': {}}
                else:
                    return {'status': 'error', 'execution_count': self.execution_count,
                            'ename': 'RubyError', 'evalue': f'Ruby execution failed with code {result.returncode}',
                            'traceback': [result.stderr] if result.stderr else []}
                    
            except subprocess.TimeoutExpired:
                return {'status': 'error', 'execution_count': self.execution_count,
                        'ename': 'TimeoutError', 'evalue': 'Ruby execution timed out',
                        'traceback': []}
            except Exception as e:
                return {'status': 'error', 'execution_count': self.execution_count,
                        'ename': 'KernelError', 'evalue': str(e),
                        'traceback': []}

if __name__ == '__main__':
    from ipykernel.kernelapp import IPKernelApp
    IPKernelApp.launch_instance(kernel_class=RubyKernel)
