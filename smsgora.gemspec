# frozen_string_literal: true

require_relative 'lib/smsgora'

Gem::Specification.new do |s|
  s.name        = 'smsgora'
  s.version     = SmsGora::VERSION
  s.summary     = 'SMS Gora SMS Gateway: official Ruby client by Tekservix'
  s.description = 'SMS Gora SMS Gateway. Send and receive SMS through your own Android phones with SMS Gora: delivery reports, scheduled and bulk sending, and signed webhooks. Works in Rails, Sinatra and plain Ruby.'
  s.authors     = ['Tekservix']
  s.email       = 'support@tekservix.com'
  s.homepage    = 'https://tekservix.com/smsgora/'
  s.license     = 'MIT'
  s.files       = Dir['lib/**/*.rb'] + %w[README.md LICENSE]
  s.required_ruby_version = '>= 2.7'
  s.metadata = {
    'homepage_uri' => 'https://tekservix.com/smsgora/',
    'documentation_uri' => 'https://tekservix.com/smsgora/docs/',
    'source_code_uri' => 'https://github.com/TekservixHQ/smsgora-ruby',
    'bug_tracker_uri' => 'https://github.com/TekservixHQ/smsgora-ruby/issues',
    'rubygems_mfa_required' => 'true'
  }
end
