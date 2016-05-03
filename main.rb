#!/usr/bin/env ruby

# TODO
# - measure win rate by starting position, see if we need to correct
# - measure historic player value by draft position
#   - does it vary over rounds? probably
#   - teach AI to use it
# - implement human trades
#   - respond first, then propose
# - "ui" for draft order, human-comprehensible
# - more interesting trades (include players in trade, multiple picks on each side
# - make it run faster
# - make AI deterministic to make training stable
# - AI passes too soon in round 1. should try harder to make the opponent spend cards, even if likely / guaranteed to lose
# - vector of per-season discount rates rather than one fixed rate

require 'rubygems'
require 'bundler/setup'

require 'cabin'
require 'colorize'

require 'active_support'
require 'active_support/dependencies'
ActiveSupport::Dependencies.autoload_paths << 'lib'

$logger = Cabin::Channel.new
$logger.subscribe(STDOUT)
$logger.level = :debug

TEAMS = 4
INITIAL_ROSTER = [4,3]
DRAFT_ROUNDS = 8

PLAYERS = [10,
           9,
           8, 8,
           7, 7,
           6, 6, 6, 6,
           5, 5, 5, 5,
           4, 4, 4, 4, 4, 4,
           3, 3, 3, 3, 3, 3,
           2, 2, 2, 2, 2, 2,
           1, 1, 1, 1, 1, 1, 1, 1,
          ]

raise unless PLAYERS.size == TEAMS * (INITIAL_ROSTER.size + DRAFT_ROUNDS)

CHAMPIONSHIPS_TO_WIN = 3

# TODO pick a sequence we like and stick with it
PERMUTATIONS = [
  [0, 1, 2, 3],
  [1, 3, 0, 2],
  [2, 1, 3, 0],
  [3, 2, 0, 1],
  [0, 3, 1, 2],
  [1, 0, 2, 3],
  [2, 3, 1, 0],
  [3, 0, 2, 1],
  [0, 2, 1, 3],
]

raise unless PERMUTATIONS.size == ((CHAMPIONSHIPS_TO_WIN - 1) * TEAMS) + 1

def permute_array(array, permutation_index)
  mapping = PERMUTATIONS[permutation_index]
  array.map { |i| mapping[i] }
end

GOFIRST_DRAFT_ORDER =  [0,1,2,3, 3,2,1,0, 3,1,0,2, 2,0,1,3, 2,1,0,3, 3,0,1,2, 2,1,0,3, 3,0,1,2]
raise unless GOFIRST_DRAFT_ORDER.size == (DRAFT_ROUNDS * TEAMS)

TEAM_NAMES = %w(Red Yellow Blue Green) # just for human labeling

#puts draft_order.map{ |d| d.join(",") }.join("\n")

# Not really very stable at all
BEST_KNOWN_PERSONALITY = {:trade=>{:discount_rate=>0.20197358138194768, :greed=>0.2246163019335792}, :semifinal=>{:pass_rate=>0.35100092192245164, :aggression=>0.1455125413275264, :score_ratio_exponent=>1.5186101104510794, :home_aggression_bonus=>2.65584984909288}, :final=>{:pass_rate=>0.024187941063476125, :aggression=>10.574063391446504, :score_ratio_exponent=>1.107944461262698, :home_aggression_bonus=>1.293352894099222}}


# TODO optimize AIs - search, GA, etc
def make_random_personality
  {
    trade: {
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
  s = ''
  s += " |".colorize(:black) + (0...(DRAFT_ROUNDS * TEAMS)).map { |dr| (dr / 10).to_s.colorize(:black) }.join("|".colorize(:black)) + "\n"
  s += " |".colorize(:black) + (0...(DRAFT_ROUNDS * TEAMS)).map { |dr| (dr % 10).to_s.colorize(:black) }.join("|".colorize(:black)) + "\n"
  draft_order.each_with_index do |season, season_idx|
    s += season_idx.to_s.colorize(:black) + "|".colorize(:black)
    s += season.map do |p|
      name = TEAM_NAMES[p].to_s
      name[0].colorize(name.downcase.to_sym)
    end.join("|".colorize(:black)) + "\n"
  end
  s
end

def play_game!(teams)
  # TODO structure this as a 2d array of picks instead of numbers
  draft_order = (0...PERMUTATIONS.size).map do |season|
    permute_array(GOFIRST_DRAFT_ORDER, season)
  end

  free_agents = PLAYERS.dup

  # Pre-game - give each team their initial roster

  teams.each do |team|
    INITIAL_ROSTER.each do |rank|
      team.roster << rank
      free_agents.delete_at(free_agents.find_index(rank))
    end
  end

  season = $logger[:season] = 0

  while teams.all? { |t| t.championships < 3 }
    $logger.info "Season starting!"

    # loop through seasons until one team has three championships
    # three phases to season: 1) draft (with trades), 2) tournament, 3) offseason (retain up to two)

    # Phase 1: Draft

    # Do a straight draft w/o trades
    free_agents.sort!.reverse!
    (0...(DRAFT_ROUNDS * TEAMS)).each do |pick_index|
      $logger[:pick] = pick_index
      on_the_clock = teams[draft_order[season][pick_index]]
      $logger.debug "#{on_the_clock.name} are on the clock"

      trade = on_the_clock.agent.request_trade_proposal(season, pick_index, draft_order)
      if trade # TODO validate trade proposal
        $logger.info "trade proposed", trade: trade.to_s
        if teams[trade.to_team_index].agent.accept_trade?(season, pick_index, draft_order, trade)
          $logger.info "trade accepted!", trade: trade.to_s
          draft_order[trade.to_season][trade.to_pick_index] = trade.from_team_index
          draft_order[trade.from_season][trade.from_pick_index] = trade.to_team_index

          now_on_the_clock = teams[draft_order[season][pick_index]] # in case this has changed in the trade we just did
          if now_on_the_clock != on_the_clock
            on_the_clock = now_on_the_clock
            $logger.info "After trade, #{on_the_clock.name} are now on the clock"
          end
        end
      end

      next_free_agent = free_agents.shift
      on_the_clock.roster <<  next_free_agent
      $logger.debug "#{on_the_clock.name} pick #{next_free_agent}"
    end

    # Phase 2: Tournament
    play_order = permute_array([0,1,2,3], season)
    east_semi = Match.new(teams[play_order[0]],teams[play_order[1]],:semifinal)
    east_winner = east_semi.play!
    $logger.info "East semifinal: #{east_semi.summary}"

    west_semi = Match.new(teams[play_order[2]],teams[play_order[3]],:semifinal)
    west_winner = west_semi.play!
    $logger.info "West semifinal: #{west_semi.summary}"

    final = Match.new(east_winner, west_winner,:final)
    champion = final.play!
    $logger.info "Final: #{final.summary}"
    $logger.info "#{champion.name} wins the season!"
    champion.championships += 1

    # Return played cards to free agency
    [east_semi, west_semi, final].each { |match| free_agents.push(*match.cards_played) }


    # Phase 3: Offseason

    # Draw down each team to best two keepers
    # TODO is there ever a reason for a team to voluntarily keep less than two? I don't think so...
    teams.each do |team|
      team.roster.sort!
      while team.roster.size > 2
        free_agents << team.roster.shift
      end
    end

    $logger.info "Standings: #{teams.map { |t| [t.name, t.championships] }}"
    $logger.info "Keepers: #{teams.map { |t| [t.name, t.roster] }}"

    season += 1
    $logger[:season] = season
  end

  victor = teams.find { |t| t.championships == 3 }
  $logger.warn "#{victor.name} have the dynasty!"

  [victor, season]
end

hall_of_fame = Array.new(20) { BEST_KNOWN_PERSONALITY.dup }

iteration = 0
checkpoint = nil
last_checkpoint = nil

require 'pp'

loop do
  iteration += 1

  # TODO Elo or other player ratings?

  # Choose players for tournament
  personalities = [hall_of_fame[0], # most recent winner
                   cross_breed(hall_of_fame[0], hall_of_fame[Random.rand(hall_of_fame.size)]), # winner and offsping
                   cross_breed(hall_of_fame[Random.rand(hall_of_fame.size)], hall_of_fame[Random.rand(hall_of_fame.size)]), # veteran offspring
                   mutate(hall_of_fame[0]) # mutant
                  ].each_with_index.map { |pers,i| pers.merge({round_robin_wins: 0}) }


  # Play a round robin of these personalities to reduce noise and eliminate any ordering biases
  # TODO play these simultaneously to speed things up
  [0,1,2,3].permutation.each do |permutation|
    personality_order = permutation.map { |perm| personalities[perm] }
    teams = personality_order.each_with_index.map { |p,i| Team.new(i, personality: p) }
    teams[0] = Team.new(0, human: true)
    winner, season = play_game!(teams)
    winner.agent.personality[:round_robin_wins] += 1 # TODO factor in win speed
  end

  round_robin_winner = personalities.max_by { |p| p[:round_robin_wins] }

  # Occasionally inject a random vet
  if (iteration % 50) == 0
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

    puts
    puts
  end
end
