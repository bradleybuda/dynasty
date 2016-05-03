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
