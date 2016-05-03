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

  def request_trade_proposal(current_season, current_pick_index, draft_order)
    return nil # TODO allow humans to propose trades
  end

  def accept_trade?(season, pick_index, draft_order, trade)
    puts
    puts "You are #{@team.name}"
    puts "Trade Proposal: #{trade.to_s}"
    puts "It is currently season #{season}, pick #{pick_index}"
    puts "Draft order:"
    puts draft_order_table(draft_order)
    puts "Y to accept, anything else to reject:"
    puts
    gets == "Y\n"
  end
end