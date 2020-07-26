$:.push File.expand_path('lib', __dir__)
require 'upyun_rails/version'

Gem::Specification.new do |s|
  s.name = 'upyun_rails'
  s.version = UpyunRails::VERSION
  s.authors = ['qinmingyuan']
  s.email = ['mingyuan0715@foxmail.com']
  s.homepage = 'https://github.com/qinmingyuan/upyun_rails'
  s.summary = 'Upyun service for activestorage'
  s.description = 'Upyun service for activestorage'
  s.license = 'MIT'

  s.files = Dir[
    '{lib}/**/*',
    'MIT-LICENSE',
    'Rakefile',
    'README.md'
  ]

  s.add_dependency 'activestorage'

  s.add_development_dependency 'sqlite3'
  s.add_development_dependency 'bundler'
  s.add_development_dependency 'rake'
end
