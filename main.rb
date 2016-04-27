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

INITIAL_DRAFT_ORDER = [
  [0,1,2,3, 3,2,1,0, 3,1,0,2, 2,0,1,3, 2,1,0,3, 3,0,1,2, 2,1,0,3, 3,0,1,2],
]

raise unless INITIAL_DRAFT_ORDER[0].size == (DRAFT_ROUNDS * TEAMS)

class Team
  attr_reader :roster
  attr_accessor :championships
  attr_reader :name

  def initialize(idx)
    @name = ["Warriors", "Spurs", "Cavs", "Celtics"][idx]
    @roster = []
    @championships = 0
  end

  def strength
    @roster.reduce(&:+)
  end
end

class MatchParticipant
  attr_reader :team
  attr_reader :cards_played

  def initialize(team)
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

  # TODO strategy!
  # for one, don't pass with more than two cards in hand if you're in the final
  # don't play all of your cards in a semifinal (unless the other guy already did and you're the home team)
  def make_move
    return if @passed

    if @team.roster.empty?
      # if out of cards, have to pass
      @passed = true
    elsif Random.rand < 0.3
      # Randomly pass
      @passed = true
    else
      # Play a random card
      @team.roster.shuffle!
      @cards_played << @team.roster.shift
    end
  end
end

class Match
  def initialize(home_team, away_team)
    @home = MatchParticipant.new(home_team)
    @away = MatchParticipant.new(away_team)
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

teams = Array.new(TEAMS) { |i| Team.new(i) }
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
  puts
  puts "Season #{season} starting!"

  # loop through seasons until one team has three championships
  # three phases to season: 1) draft (with trades), 2) tournament, 3) offseason (retain up to two)

  # Phase 1: Draft

  # Do a straight draft w/o trades
  # TODO permute draft order by season
  free_agents.sort!.reverse!
  INITIAL_DRAFT_ORDER[0].each do |team_to_draft_next|
    team = teams[team_to_draft_next]
    next_free_agent = free_agents.shift
    team.roster <<  next_free_agent
    puts "#{team.name} pick #{next_free_agent}"
  end

  # Phase 2: Tournament
  # TODO permute home/away and matchups by season
  east_semi = Match.new(teams[0],teams[1])
  east_winner = east_semi.play!
  puts "East semifinal:"
  puts east_semi.summary

  west_semi = Match.new(teams[2],teams[3])
  west_winner = west_semi.play!
  puts "West semifinal:"
  puts west_semi.summary

  final = Match.new(east_winner, west_winner)
  champion = final.play!
  puts "Final:"
  puts final.summary
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

  puts "Keepers:"
  p teams

  season += 1
end
