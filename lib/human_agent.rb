require 'colorize'

class HumanAgent
  def initialize(team)
    @team = team
  end

  def make_move(match)
    puts
    puts "You are #{@team.name}"
    puts "Your hand: #{@team.roster.sort}"
    puts "#{match.opponent(@team).name} has played #{match.opponent_card_count(@team)} cards"
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

  def request_trade_proposal(current_season, current_pick_index, draft_order, current_free_agents)
    return nil # TODO allow humans to propose trades
  end

  # TODO would be nice to see which numbers go to which picks
  # TODO also have AI use this context for current season instead of historic tables
  def accept_trade?(season, pick_index, draft_order, trade, current_free_agents)
    puts
    puts "You are #{@team.name}"
    puts "Trade Proposal: #{trade.to_s}"
    puts "It is currently season #{season}, pick #{pick_index}"
    puts "The current free agents are: #{current_free_agents}"
    puts "Draft order:"
    puts draft_order_table(draft_order)
    puts "Y to accept, anything else to reject:"
    puts
    gets == "Y\n"
  end

  private

  def draft_order_table(draft_order)
    draft_rounds = draft_order[0].size

    s = ''
    s += " |".colorize(:black) + (0...draft_rounds).map { |dr| (dr / 10).to_s.colorize(:black) }.join("|".colorize(:black)) + "\n"
    s += " |".colorize(:black) + (0...draft_rounds).map { |dr| (dr % 10).to_s.colorize(:black) }.join("|".colorize(:black)) + "\n"
    draft_order.each_with_index do |season, season_idx|
      s += season_idx.to_s.colorize(:black) + "|".colorize(:black)
      s += season.map do |p|
        name = Team::TEAM_NAMES[p].to_s
        name[0].colorize(name.downcase.to_sym)
      end.join("|".colorize(:black)) + "\n"
    end
    s
  end
end
