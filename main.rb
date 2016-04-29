#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'

require 'cabin'

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

#puts draft_order.map{ |d| d.join(",") }.join("\n")

# Not really very stable at all
BEST_KNOWN_PERSONALITY = {:semifinal=>{:pass_rate=>0.4283637209326171, :aggression=>0.9269851836025846, :score_ratio_exponent=>5.207624965185063, :home_aggression_bonus=>2.036206470772239}, :final=>{:pass_rate=>0.03887686260875057, :aggression=>4.856051743802492, :score_ratio_exponent=>2.662435833063665, :home_aggression_bonus=>2.0043335941280818}}

# TODO optimize AIs - search, GA, etc
def make_random_personality
  {
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
  [:semifinal, :final].each do |stage|
    child[stage] = {}
    [:pass_rate, :aggression, :score_ratio_exponent, :home_aggression_bonus].each do |attr|
      child[stage][attr] = p[stage][attr] * (Random.rand * 0.1 + 0.95)
    end
  end
  child
end

class HumanAgent
  def initialize(team)
    @team = team
  end

  def make_move(match)
    puts
    puts "You are the #{@team.name}"
    puts "Your hand: #{@team.roster.sort}"
    puts "Opponent has played #{match.opponent_card_count(@team)} cards"
    puts
    puts "Card to play, or blank to pass?"
    play = gets
    play.chomp!
    if play.empty?
      :pass
    else
      play.to_i
    end
  end
end

class AiAgent
  attr_reader :personality

  def initialize(team, personality)
    @team = team
    @personality = personality
  end

  def play_card(card)
    $logger.debug "playing card", card: card
    card
  end

  def play_random_card(aggression)
    pick_index = (Random.rand * aggression * @team.roster.size).floor
    if pick_index > @team.roster.size - 1
      pick_index = @team.roster.size - 1
    end

    play_card(@team.roster.sort[pick_index])
  end

  def throw_off_or_pass
    if @team.roster.size > 2
      play_card(@team.roster.sort.first)
    else
      :pass
    end
  end

  def make_move(match)
    # Strategic TODOs
    # * don't pass if you're the opener and you have more than two cards
    # * in general, AI passes too much early on. pass less if you have more cards?
    # * Size opponent's play (min, max, mean) based on knowledge of their hand and # of cards played
    # * Play until your total exceeds your best estimate of their total, and no more
    # * don't play all of your cards in a semifinal (unless the other side of the bracket already did and you're the home team)
    # * pass rate paramaterized on cards played / remaining
    # * if the opponent has passed, play the smallest card you can to win

    # Calculate some hand metrics
    opponent_starting_hand = match.opponent_starting_hand(@team)
    opponent_card_count = match.opponent_card_count(@team)

    # TODO this is unused, find something to do with it
    #opponent_hand_estimates = Array.new(100) { opponent_starting_hand.shuffle.first(opponent_card_count).reduce(&:+) || 0 }
    #opponent_hand_estimate = opponent_hand_estimates.reduce(&:+).to_f / opponent_hand_estimates.size.to_f

    # TODO much of this context is cachable from play to play
    metrics = {
      worst_current_opponent_score: opponent_starting_hand.sort.first(opponent_card_count).reduce(&:+) || 0,
      best_current_opponent_score: opponent_starting_hand.sort.last(opponent_card_count).reduce(&:+) || 0,
      #estimated_current_opponent_score: opponent_hand_estimate,
      best_possible_opponent_score: opponent_starting_hand.reduce(&:+) || 0,
      my_score: match.my_score(@team),
      my_best_possible_score: match.starting_hand(@team).reduce(&:+) || 0,
    }

    if match.opponent_has_passed(@team)
      metrics[:best_possible_opponent_score] = metrics[:best_current_opponent_score]
    end

    $logger.debug "hand analysis", metrics

    match_personality = @personality[match.stage]

    score_ratio = metrics[:my_best_possible_score].to_f / (metrics[:best_possible_opponent_score].to_f + 1.0)
    aggression = match_personality[:aggression] * (score_ratio ** match_personality[:score_ratio_exponent])
    if match.is_home_team?(@team)
      aggression *= match_personality[:home_aggression_bonus]
    end

    $logger.debug "Aggression for this play is: #{aggression}"

    hand_load_factor = @team.roster.size.to_f / 10.0
    effective_pass_rate = match_personality[:pass_rate] / (aggression * hand_load_factor)
    $logger.debug "Current pass rate is: #{effective_pass_rate}"

    needed_for_guaranteed_lead = metrics[:best_current_opponent_score] - metrics[:my_score] + 1 # TODO include home adv here
    wasted_cards = @team.roster.sort[0...-2]
    leapfrog_cards = wasted_cards.find_all { |w| w > needed_for_guaranteed_lead }
    $logger.debug("leapfrog?", needed_for_guaranteed_lead: needed_for_guaranteed_lead, wasted_cards: wasted_cards, leapfrog_cards: leapfrog_cards)

    if metrics[:my_score] > metrics[:best_possible_opponent_score]
      $logger.debug "Victory is guaranteed, passing"
      :pass

    elsif metrics[:my_best_possible_score] < metrics[:worst_current_opponent_score]
      $logger.debug "No win situation, throwing off"
      throw_off_or_pass

    elsif (needed_for_guaranteed_lead > 0) && !leapfrog_cards.empty?
      # We can take the lead by playing off a card that we would lose anyway in the offseason, so do it
      # This might not be optimal but it's better than the AI's current behavior
      $logger.debug "can take the lead with any of #{leapfrog_cards}, will play a random one"
      play_card(leapfrog_cards.shuffle.first) # TODO paramaterize on aggression rather than playing random?

    elsif (match.stage == :final) && (@team.roster.size > 2)
      # TODO No point in passing, *but* I maybe shouldn't be playing by best cards in this mode
      $logger.debug "Will never pass in the final with more than two cards left"
      play_random_card(aggression)
    elsif Random.rand < effective_pass_rate
      :pass
    else
      play_random_card(aggression)
    end
  end
end


class Team
  attr_reader :roster
  attr_accessor :championships
  attr_reader :name
  attr_reader :agent

  def initialize(idx, human: false, personality: make_random_personality)
    @name = ["Warriors", "Spurs", "Cavs", "Celtics"][idx] # TODO naming is broken-ish
    @roster = []
    @championships = 0

    @agent = human ? HumanAgent.new(self) : AiAgent.new(self, personality)
  end

  def strength
    @roster.reduce(&:+)
  end
end

class MatchParticipant
  attr_reader :team
  attr_reader :cards_played

  def initialize(match, team)
    @match = match
    @team = team
    @cards_played = []
    @passed = false
  end

  def passed?
    @passed
  end

  def score
    if @cards_played.empty?
      0
    else
      @cards_played.reduce(&:+)
    end
  end

  def make_move
    return if @passed

    if @team.roster.empty?
      # if out of cards, have to pass
      @passed = true
      $logger.info "#{@team.name} are out of cards, passing"
    else
      play = @team.agent.make_move(@match)
      if play == :pass
        @passed = true
        $logger.info "#{@team.name} are electing to pass"
      else
        if play_index = @team.roster.find_index(play)
          @cards_played << play
          @team.roster.delete_at(play_index)
          $logger.info "#{@team.name} played" # #{play}" # TODO hide from human
        else
          raise "illegal play: #{play}"
        end
      end
    end
  end
end

class Match
  attr_reader :stage

  def initialize(home_team, away_team, stage)
    @home = MatchParticipant.new(self, home_team)
    @away = MatchParticipant.new(self, away_team)
    @stage = stage

    @starting_hands = {
      home_team => home_team.roster.dup,
      away_team => away_team.roster.dup,
    }
  end

  def my_score(team)
    [@home, @away].find { |mp| mp.team == team }.cards_played.reduce(&:+) || 0
  end

  def starting_hand(team)
    @starting_hands[team]
  end

  def opponent_has_passed(team)
    [@home, @away].find { |mp| mp.team != team }.passed?
  end

  def opponent_starting_hand(team)
    @starting_hands[opponent(team)]
  end

  def opponent_card_count(team)
    [@home, @away].find { |mp| mp.team != team }.cards_played.count
  end

  def opponent(team)
    [@home, @away].map(&:team).find { |t| t != team }
  end

  def is_home_team?(team)
    @home.team == team
  end

  def play!
    $logger.info "#{@home.team.name} have #{@home.team.roster.sort}"
    $logger.info "#{@away.team.name} have #{@away.team.roster.sort}"

    until [@away,@home].all?(&:passed?)
      @away.make_move
      @home.make_move
    end

    $logger.info "#{@home.team.name} played #{@home.cards_played.sort} for #{@home.score}"
    $logger.info "#{@away.team.name} played #{@away.cards_played.sort} for #{@away.score}"

    if @away.score > @home.score
      return @away.team
    else
      return @home.team # home wins in ties, TODO better tiebreaker
    end
  end

  def cards_played
    @home.cards_played + @away.cards_played
  end

  def summary
    "#{@away.team.name} #{@away.score}, #{@home.team.name} #{@home.score}"
  end
end

def play_game!(teams)
  draft_order = (0...PERMUTATIONS.size).map do |season|
    permute_array(GOFIRST_DRAFT_ORDER, season)
  end

  teams[0] = Team.new(0, human: true)
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
    # TODO permute draft order by season
    free_agents.sort!.reverse!
    draft_order[season].each do |team_to_draft_next|
      team = teams[team_to_draft_next]
      next_free_agent = free_agents.shift
      team.roster <<  next_free_agent
      $logger.debug "#{team.name} pick #{next_free_agent}"
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
  victor
end

hall_of_fame = Array.new(20) { make_random_personality }

iteration = 0
checkpoint = nil
last_checkpoint = nil

require 'pp'

loop do
  iteration += 1

  # Make tournament
  personalities = [hall_of_fame[0], # most recent winner
                   cross_breed(hall_of_fame[0], hall_of_fame[Random.rand(hall_of_fame.size)]), # winner and offsping
                   cross_breed(hall_of_fame[Random.rand(hall_of_fame.size)], hall_of_fame[Random.rand(hall_of_fame.size)]), # veteran offspring
                   mutate(hall_of_fame[0]) # mutant
                  ]

  # Overwrite with "best" AIs
  personalities = Array.new(4) { BEST_KNOWN_PERSONALITY.dup }

  # Occasionally inject a random vet
  if (iteration % 50) == 0
    hall_of_fame.pop
    hall_of_fame.unshift(make_random_personality)
  end

  teams = personalities.shuffle.each_with_index.map { |p,i| Team.new(i, personality: p) }
  winner = play_game!(teams) # TODO play in every position to reduce noise and smooth any ordering biases

  # Age one team out of HoF
  hall_of_fame.pop
  hall_of_fame.unshift(winner.agent.personality)

  $logger.warn "winner", winner.agent.personality


  if (iteration % 1000) == 0
    p "best known:"
    p hall_of_fame[0]

    p "current hof:"
    hof_matrix = hall_of_fame.map do |hof|
      row = []
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
