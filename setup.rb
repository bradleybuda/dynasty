require 'rubygems'
require 'bundler/setup'

require 'cabin'

require 'active_support'
require 'active_support/dependencies'
ActiveSupport::Dependencies.autoload_paths << 'lib'

# TODO move to per-class loggers?
$logger = Cabin::Channel.new
$logger.subscribe(STDOUT)
$logger.level = :debug
