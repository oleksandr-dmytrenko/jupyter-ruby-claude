Gem::Specification.new do |spec|
  spec.name          = 'rosi'
  spec.version       = '0.1.0'
  spec.authors       = ['']
  spec.email         = ['']
  spec.summary       = 'Nori Jupyter'
  spec.description   = 'Nori Jupyter'
  spec.homepage      = ''
  spec.license       = 'MIT'

  spec.files         = Dir['lib/**/*']
  spec.require_paths = ['lib']

  spec.add_dependency 'zeitwerk', '~> 2.6'
  spec.add_development_dependency 'bundler', '~> 2.5'
  spec.required_ruby_version = '>= 3.3.4'
end

# Optional: Add any additional dependencies here
# gemspec.add_dependency 'your_dependency', '~> 1.0'
