Gem::Specification.new do |spec|
  spec.name          = 'rosi'
  spec.version       = '0.2.0'
  spec.authors       = ['Rosi Team']
  spec.email         = ['team@rosi.dev']
  spec.summary       = 'Nori Jupyter - Ruby 3.3.4 Compatible'
  spec.description   = 'Nori Jupyter service loader with Ruby 3.3.4 compatibility and enhanced error handling'
  spec.homepage      = ''
  spec.license       = 'MIT'

  spec.files         = Dir['lib/**/*', 'README*', 'LICENSE*']
  spec.require_paths = ['lib']

  # Specify Ruby version compatibility
  spec.required_ruby_version = '>= 3.0.0'

  # Runtime dependencies
  spec.add_dependency 'fileutils', '~> 1.7'

  # Development dependencies
  spec.add_development_dependency 'bundler', '~> 2.5'
  spec.add_development_dependency 'rake', '~> 13.0'
  
  # Metadata for better gem management (removed empty URIs for Ruby 3.3+ compatibility)
  spec.metadata = {
    'rubygems_mfa_required' => 'true'
  }
end
