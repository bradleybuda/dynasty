class Trade < Struct.new(:to_team_index, :to_season, :to_pick_index, :from_team_index, :from_season, :from_pick_index)
  def team_gets(team_index, season, pick_index)
    name = Team::TEAM_NAMES[team_index] # TODO naming is broken-ish
    "#{name} get pick #{pick_index} in season #{season}"
  end

  def to_s
    "#{team_gets(from_team_index, to_season, to_pick_index)}, #{team_gets(to_team_index, from_season, from_pick_index)}"
  end
end
