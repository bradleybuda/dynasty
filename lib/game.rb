class Game
  # Base game parameters
  TEAM_COUNT = 4
  INITIAL_ROSTER = [4,3]
  PICKS_PER_TEAM = 8
  PICKS_PER_ROUND = TEAM_COUNT * PICKS_PER_TEAM
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

  raise unless PLAYERS.size == TEAM_COUNT * (INITIAL_ROSTER.size + PICKS_PER_TEAM)

  CHAMPIONSHIPS_TO_WIN = 3

  # TODO do we like this sequence? Last round might be unfair
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

  raise unless PERMUTATIONS.size == ((CHAMPIONSHIPS_TO_WIN - 1) * TEAM_COUNT) + 1

  DRAFT_ORDER = [
    0,1,2,3,
    3,2,1,0,
    3,1,0,2,
    2,0,1,3,
    2,1,0,3,
    3,0,1,2,
    2,1,0,3,
    3,0,1,2
  ]

  raise unless DRAFT_ORDER.size == PICKS_PER_ROUND

  def initialize(teams)
    raise unless teams.size == TEAM_COUNT
    @teams = teams
  end

  def play!
    # TODO structure this as a 2d array of picks instead of numbers
    draft_order = (0...PERMUTATIONS.size).map do |season|
      permute_array(DRAFT_ORDER, season)
    end

    free_agents = PLAYERS.dup

    # Pre-game - give each team their initial roster

    @teams.each do |team|
      INITIAL_ROSTER.each do |rank|
        team.roster << rank
        free_agents.delete_at(free_agents.find_index(rank))
      end
    end

    season = -1

    while @teams.all? { |t| t.championships < 3 }
      season += 1
      $logger[:season] = season
      $logger.info "Season starting!"

      # loop through seasons until one team has three championships
      # three phases to season: 1) draft (with trades), 2) tournament, 3) offseason (retain up to two)

      # Phase 1: Draft

      # Do a straight draft w/o trades
      free_agents.sort!.reverse!
      (0...PICKS_PER_ROUND).each do |pick_index|
        $logger[:pick] = pick_index
        on_the_clock = @teams[draft_order[season][pick_index]]
        $logger.debug "#{on_the_clock.name} are on the clock"

        trade = on_the_clock.agent.request_trade_proposal(season, pick_index, draft_order, free_agents)
        if trade # TODO validate trade proposal
          $logger.info "trade proposed", trade: trade.to_s
          if @teams[trade.to_team_index].agent.accept_trade?(season, pick_index, draft_order, trade, free_agents)
            $logger.info "trade accepted!", trade: trade.to_s
            draft_order[trade.to_season][trade.to_pick_index] = trade.from_team_index
            draft_order[trade.from_season][trade.from_pick_index] = trade.to_team_index

            now_on_the_clock = @teams[draft_order[season][pick_index]] # in case this has changed in the trade we just did
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
      east_semi = Match.new(@teams[play_order[0]],@teams[play_order[1]],:semifinal)
      east_winner = east_semi.play!
      $logger.info "East semifinal: #{east_semi.summary}"

      west_semi = Match.new(@teams[play_order[2]],@teams[play_order[3]],:semifinal)
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
      @teams.each do |team|
        team.roster.sort!
        while team.roster.size > 2
          free_agents << team.roster.shift
        end
      end

      $logger.info "Standings: #{@teams.map { |t| [t.name, t.championships] }}"
      $logger.info "Keepers: #{@teams.map { |t| [t.name, t.roster] }}"
    end

    victor = @teams.find { |t| t.championships == 3 }
    $logger.warn "#{victor.name} have the dynasty!"

    [victor, season]
  end

  private

  def permute_array(array, permutation_index)
    mapping = PERMUTATIONS[permutation_index]
    array.map { |i| mapping[i] }
  end
end
