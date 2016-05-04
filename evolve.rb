#!/usr/bin/env ruby

require './setup'

$logger.level = :error
Evolver.new.run_forever!
