#!/usr/bin/env ruby

# TODO
# - measure win rate by starting position, see if we need to correct
# - measure historic player value by draft position
#   - does it vary over rounds? probably
#   - teach AI to use it
# - implement human trade propsals
# - more interesting trades (include players in trade, multiple picks on each side
# - make it run faster
# - AI passes too soon in round 1. should try harder to make the opponent spend cards, even if likely / guaranteed to lose
# - vector of per-season discount rates rather than one fixed rate
# - allow UI to trade later picks

require 'rubygems'
require 'bundler/setup'

require 'cabin'
require 'colorize'

require 'active_support'
require 'active_support/dependencies'
ActiveSupport::Dependencies.autoload_paths << 'lib'

# TODO move to per-class loggers?
$logger = Cabin::Channel.new
$logger.subscribe(STDOUT)
$logger.level = :info

# Seems to be getting more stable?!?
BEST_KNOWN_PERSONALITY = {:trade=>{:frequency=>0.9516041261893311, :discount_rate=>0.06350624921041632, :greed=>0.03890549363963399}, :semifinal=>{:pass_rate=>0.3739092425078163, :aggression=>0.6981277012787459, :score_ratio_exponent=>1.9134131331172328, :home_aggression_bonus=>1.316660849987346}, :final=>{:pass_rate=>0.24804306198435205, :aggression=>6.965948529802139, :score_ratio_exponent=>1.264220603096014, :home_aggression_bonus=>1.52822687647762}}

# TODO optimize AIs - search, GA, etc
def make_random_personality
  {
    trade: {
      frequency: Random.rand,
      discount_rate: Random.rand,
      greed: Random.rand,
    },
    semifinal: {
      pass_rate: Random.rand,
      aggression: Random.rand * 10.0,
      score_ratio_exponent: Random.rand * 5.0,
      home_aggression_bonus: 1.0 + Random.rand,
    },
    final: {
      pass_rate: Random.rand,
      aggression: Random.rand * 10.0,
      score_ratio_exponent: Random.rand * 5.0,
      home_aggression_bonus: 1.0 + Random.rand,
    },
  }
end

def cross_breed(a,b)
  child = {}

  child[:trade] = {
    frequency: [a,b].shuffle.first[:trade][:frequency],
    discount_rate: [a,b].shuffle.first[:trade][:discount_rate],
    greed: [a,b].shuffle.first[:trade][:greed],
  }

  [:semifinal, :final].each do |stage|
    child[stage] = {}
    [:pass_rate, :aggression, :score_ratio_exponent, :home_aggression_bonus].each do |attr|
      child[stage][attr] = [a,b].shuffle.first[stage][attr]
    end
  end

  child
end

def mutate(p)
  child = {}

  child[:trade] = {
    frequency: p[:trade][:frequency] * (Random.rand * 0.1 + 0.95),
    discount_rate: p[:trade][:discount_rate] * (Random.rand * 0.1 + 0.95),
    greed: p[:trade][:greed] * (Random.rand * 0.1 + 0.95),
  }

  [:semifinal, :final].each do |stage|
    child[stage] = {}
    [:pass_rate, :aggression, :score_ratio_exponent, :home_aggression_bonus].each do |attr|
      child[stage][attr] = p[stage][attr] * (Random.rand * 0.1 + 0.95)
    end
  end
  child
end

def draft_order_table(draft_order)
  draft_rounds = draft_order[0].size

  s = ''
  s += " |".colorize(:black) + (0...draft_rounds).map { |dr| (dr / 10).to_s.colorize(:black) }.join("|".colorize(:black)) + "\n"
  s += " |".colorize(:black) + (0...draft_rounds).map { |dr| (dr % 10).to_s.colorize(:black) }.join("|".colorize(:black)) + "\n"
  draft_order.each_with_index do |season, season_idx|
    s += season_idx.to_s.colorize(:black) + "|".colorize(:black)
    s += season.map do |p|
      name = Team::TEAM_NAMES[p].to_s
      name[0].colorize(name.downcase.to_sym)
    end.join("|".colorize(:black)) + "\n"
  end
  s
end

hall_of_fame = Array.new(20) { BEST_KNOWN_PERSONALITY.dup }

iteration = 0
checkpoint = nil
last_checkpoint = nil

require 'pp'

dynasties_by_position = [0,0,0,0]
distribution_of_season_counts = [0,0,0,0,0,0,0,0,0]

loop do
  iteration += 1

  # TODO Elo or other player ratings?

  # Choose players for tournament
  personalities = [hall_of_fame[0], # most recent winner
                   cross_breed(hall_of_fame[0], hall_of_fame[Random.rand(hall_of_fame.size)]), # winner and offsping
                   cross_breed(hall_of_fame[Random.rand(hall_of_fame.size)], hall_of_fame[Random.rand(hall_of_fame.size)]), # veteran offspring
                   mutate(hall_of_fame[0]) # mutant
                  ].each_with_index.map { |pers,i| pers.merge({round_robin_wins: 0, cumulative_seasons_for_wins: 0}) }


  # Play a round robin of these personalities to reduce noise and eliminate any ordering biases
  # TODO play these simultaneously to speed things up
  [0,1,2,3].permutation.each do |permutation|
    personality_order = permutation.map { |perm| personalities[perm] }
    teams = personality_order.each_with_index.map { |p,i| Team.new(i, personality: p) }
    teams[0] = Team.new(0, human: true)
    winner, season = Game.new(teams).play!
    winner.agent.personality[:round_robin_wins] += 1
    winner.agent.personality[:cumulative_seasons_for_wins] += season
    dynasties_by_position[personality_order.find_index(winner.agent.personality)] += 1
    distribution_of_season_counts[season] += 1
  end

  round_robin_winner = personalities.max_by { |p| [p[:round_robin_wins], -p[:cumulative_seasons_for_wins]] }

  # Occasionally inject a random vet
  if (iteration % 23) == 0
    hall_of_fame.pop
    hall_of_fame.unshift(make_random_personality)
  end

  # Add the winner to the HoF
  hall_of_fame.pop
  hall_of_fame.unshift(round_robin_winner)

  $logger.warn "winner", round_robin_winner

  if (iteration % 100) == 0
    p "best known:"
    p hall_of_fame[0]

    p "current hof:"
    hof_matrix = hall_of_fame.map do |hof|
      row = []
      row << (hof[:trade][:frequency] * 100).to_i
      row << (hof[:trade][:discount_rate] * 100).to_i
      row << (hof[:trade][:greed] * 100).to_i

      [:semifinal, :final].each do |stage|
        [:pass_rate, :aggression, :score_ratio_exponent, :home_aggression_bonus].each do |attr|
          row << (hof[stage][attr] * 100).to_i
        end
      end
      row
    end
    pp hof_matrix

    checkpoint = hof_matrix[0]

    if last_checkpoint
      drift = Math.sqrt(checkpoint.zip(last_checkpoint).map { |(a,b)| (a - b) ** 2 }.inject(&:+))
      p drift
    end
    last_checkpoint = checkpoint

    p "dynasties by pos"
    p dynasties_by_position
    p distribution_of_season_counts

    puts
    puts
  end
end
