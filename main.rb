require 'logger'

$logger = Logger.new(STDOUT)
$logger.level = Logger::DEBUG


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

# TODO optimize AIs - search, GA, etc
PERSONALITIES = {
  "Warriors" => {pass_rates: {final: 0.1, semifinal: 0.3}, greedy: true, dont_waste_cards: true},
  "Spurs" => {pass_rates: {final: 0.2, semifinal: 0.5}, greedy: true, dont_waste_cards: true},
  "Cavs" => {pass_rates: {final: 0.2, semifinal: 0.3}, greedy: true, dont_waste_cards: true},
  "Celtics" => {pass_rates: {final: 0.1, semifinal: 0.6}, greedy: true, dont_waste_cards: true},
}

class HumanAgent
  def initialize(team)
    @team = team
  end

  def make_move(match)
    puts "You are the #{@team.name}"
    puts "Your hand: #{@team.roster.sort}"
    puts "Card to play, or blank to pass?"
    play = gets
    play.chomp!
    if play.empty?
      :pass
    else
      # TODO engine should validate play
      play.to_i
    end
  end
end

class AiAgent
  def initialize(team, personality)
    @team = team
    @personality = personality
  end

  # TODO aggression parameter - don't be strictly random or greedy, but progressively slow
  def make_move_by_pick
    if @personality[:greedy]
      @team.roster.sort.last
    else
      @team.roster.shuffle.first
    end
  end

  def throw_off_or_pass
    if @team.roster.size > 2
      @team.roster.sort.first
    else
      :pass
    end
  end

  def make_move(match)
    # Strategic TODOs
    # * Size opponent's play (min, max, mean) based on knowledge of their hand and # of cards played
    # * Determine if it's impossible to win and give up (min exceeds your hand total)
    # * Determine if you've already won and stop playing (max is below your played card)
    # * Play until your total exceeds your best estimate of their total, and no more
    # * don't play all of your cards in a semifinal (unless the other side of the bracket already did and you're the home team)
    # * don't pass if you're the opener and you have more than two cards
    # * pass rate paramaterized on cards played / remaining

    # Calculate some hand metrics
    opponent_starting_hand = match.opponent_starting_hand(@team)
    opponent_card_count = match.opponent_card_count(@team)

    metrics = {
      worst_current_opponent_score: opponent_starting_hand.sort.first(opponent_card_count).reduce(&:+) || 0,
      best_current_opponent_score: opponent_starting_hand.sort.last(opponent_card_count).reduce(&:+) || 0,
      best_possible_opponent_score: opponent_starting_hand.reduce(&:+) || 0,
      my_score: match.my_score(@team),
      my_best_possible_score: match.starting_hand(@team).reduce(&:+) || 0,
    }

    if match.opponent_has_passed(@team)
      metrics[:best_possible_opponent_score] = metrics[:best_current_opponent_score]
    end

    $logger.debug "Hand analysis: #{metrics.inspect}"

    if metrics[:my_score] > metrics[:best_possible_opponent_score]
      $logger.debug "Victory is guaranteed, passing"
      :pass
    elsif metrics[:my_best_possible_score] < metrics[:worst_current_opponent_score]
      $logger.debug "No win situation, throwing off"
      throw_off_or_pass
    elsif (@personality[:dont_waste_cards] && (match.stage == :final) && (@team.roster.size > 2))
      # TODO No point in passing, *but* I should be playing my worst cards in this mode
      make_move_by_pick
    elsif Random.rand < @personality[:pass_rates][match.stage]
      :pass
    else
      make_move_by_pick
    end
  end
end


class Team
  attr_reader :roster
  attr_accessor :championships
  attr_reader :name
  attr_reader :agent

  def initialize(idx, human: false)
    @name = ["Warriors", "Spurs", "Cavs", "Celtics"][idx]
    @roster = []
    @championships = 0

    @agent = human ? HumanAgent.new(self) : AiAgent.new(self, PERSONALITIES[@name])
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
      $logger.debug "#{@team.name} are out of cards, passing"
    else
      play = @team.agent.make_move(@match)
      if play == :pass
        @passed = true
        $logger.debug "#{@team.name} are electing to pass"
      else
        if play_index = @team.roster.find_index(play)
          @cards_played << play
          @team.roster.delete_at(play_index)
          $logger.debug "#{@team.name} played a card"
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

  def play!
    $logger.debug "#{@home.team.name} have #{@home.team.roster.sort}"
    $logger.debug "#{@away.team.name} have #{@away.team.roster.sort}"

    until [@away,@home].all?(&:passed?)
      @away.make_move
      @home.make_move
    end

    $logger.debug "#{@home.team.name} played #{@home.cards_played.sort} for #{@home.score}"
    $logger.debug "#{@away.team.name} played #{@away.cards_played.sort} for #{@away.score}"

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

def play_game!
  draft_order = (0...PERMUTATIONS.size).map do |season|
    permute_array(GOFIRST_DRAFT_ORDER, season)
  end

  teams = Array.new(TEAMS) { |i| Team.new(i) }
  #teams[0] = Team.new(0, human: true)
  teams.shuffle!
  free_agents = PLAYERS.dup

  # Pre-game - give each team their initial roster

  teams.each do |team|
    INITIAL_ROSTER.each do |rank|
      team.roster << rank
      free_agents.delete_at(free_agents.find_index(rank))
    end
  end

  season = 0

  while teams.all? { |t| t.championships < 3 }
    $logger.debug "Season #{season} starting!"

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
    $logger.debug "East semifinal: #{east_semi.summary}"

    west_semi = Match.new(teams[play_order[2]],teams[play_order[3]],:semifinal)
    west_winner = west_semi.play!
    $logger.debug "West semifinal: #{west_semi.summary}"

    final = Match.new(east_winner, west_winner,:final)
    champion = final.play!
    $logger.debug "Final: #{final.summary}"
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

    $logger.debug "Keepers: #{teams.inspect}"

    season += 1
  end

  teams.find { |t| t.championships == 3 }
end

win_rate = {}

1.times do
  winner = play_game!
  win_rate[winner.name] ||= 0
  win_rate[winner.name] += 1
end

$logger.info PERSONALITIES.inspect
$logger.info win_rate.inspect
