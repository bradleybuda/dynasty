#!/usr/bin/env ruby

require './setup'

$logger.level = :info

teams = [
  Team.new(0, human: true),
  Team.new(1, personality: Evolver::BEST_KNOWN_PERSONALITY),
  Team.new(2, personality: Evolver::BEST_KNOWN_PERSONALITY),
  Team.new(3, personality: Evolver::BEST_KNOWN_PERSONALITY),
]

Game.new(teams).play!
