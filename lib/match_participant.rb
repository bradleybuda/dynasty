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
