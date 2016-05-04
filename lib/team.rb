class Team
  TEAM_NAMES = %w(Red Yellow Blue Green) # just for human labeling

  attr_reader :idx
  attr_reader :roster
  attr_accessor :championships
  attr_reader :name
  attr_reader :agent

  def initialize(idx, human: false, personality: nil)
    @idx = idx
    @name = TEAM_NAMES[@idx] # TODO naming is broken-ish
    @roster = []
    @championships = 0

    @agent = if human
               HumanAgent.new(self)
             else
               raise unless personality
               AiAgent.new(self, personality)
             end
  end

  def strength
    @roster.reduce(&:+)
  end
end
