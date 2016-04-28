require 'logger'

$logger = Logger.new(STDOUT)
$logger.level = Logger::INFO


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

PERSONALITIES = {
  "Warriors" => {pass_rates: {final: 0.1, semifinal: 0.3}, greedy: true, dont_waste_cards: true},
  "Spurs" => {pass_rates: {final: 0.2, semifinal: 0.5}, greedy: true, dont_waste_cards: true},
  "Cavs" => {pass_rates: {final: 0.2, semifinal: 0.3}, greedy: true, dont_waste_cards: true},
  "Celtics" => {pass_rates: {final: 0.1, semifinal: 0.6}, greedy: true, dont_waste_cards: true},
}


# TODO strategy!
# don't play all of your cards in a semifinal (unless the other guy already did and you're the home team)
class AiAgent
  def initialize(team, personality)
    @team = team
    @personality = personality
  end

  def make_move_by_pick
    if @personality[:greedy]
      @team.roster.sort.last
    else
      @team.roster.shuffle.first
    end
  end

  def make_move(stage)
    if (@personality[:dont_waste_cards] && (stage == :final) && (@team.roster.size > 2))
      # No point in passing
      make_move_by_pick
    elsif Random.rand < @personality[:pass_rates][stage]
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

  def initialize(idx)
    @name = ["Warriors", "Spurs", "Cavs", "Celtics"][idx]
    @roster = []
    @championships = 0
    @agent = AiAgent.new(self, PERSONALITIES[@name])
  end

  def strength
    @roster.reduce(&:+)
  end
end

class MatchParticipant
  attr_reader :team
  attr_reader :cards_played

  def initialize(team, stage)
    @team = team
    @cards_played = []
    @passed = false
    @stage = stage
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
    else
      play = @team.agent.make_move(@stage)
      if play == :pass
        @passed = true
      else
        @cards_played << play
        @team.roster.delete_at(@team.roster.find_index(play))
      end
    end
  end
end

class Match
  def initialize(home_team, away_team, stage)
    @home = MatchParticipant.new(home_team, stage)
    @away = MatchParticipant.new(away_team, stage)
  end

  def play!
    until [@away,@home].all?(&:passed?)
      @away.make_move
      @home.make_move
    end

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

10000.times do
  winner = play_game!
  win_rate[winner.name] ||= 0
  win_rate[winner.name] += 1
end

$logger.info PERSONALITIES.inspect
$logger.info win_rate.inspect
