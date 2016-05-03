# TODO eliminate as many "sort"s as I can, they are likely redundant
class AiAgent
  attr_reader :personality

  def initialize(team, personality)
    @team = team
    @personality = personality
  end

  def play_card(card)
    $logger.debug "playing card", card: card
    card
  end

  def play_card_with_aggression(aggression, card_set: @team.roster)
    pick_index = (aggression * card_set.size).floor
    if pick_index > card_set.size - 1
      pick_index = card_set.size - 1
    end

    play_card(card_set.sort[pick_index])
  end

  def throw_off_or_pass
    if @team.roster.size > 2
      play_card(@team.roster.sort.first)
    else
      :pass
    end
  end

  def find_remaining_picks(draft_order, team_indices, current_season, current_pick_index)
    picks = []
    draft_order.each_with_index do |season_draft_order, season|
      next if season < current_season
      season_draft_order.each_with_index do |pick, pick_index|
        next if (season == current_season) && (pick_index < current_pick_index)

        if team_indices.member? pick
          picks << {team_index: pick, season: season, pick_index: pick_index}
        end
      end
    end

    picks
  end

  def pick_value(current_season, pick_season, pick_index)
    # TODO measure real values for player at pick, instead of ideal; this is an over-estimate due to keepers
    Game::PLAYERS[pick_index] * ((1 - @personality[:trade][:discount_rate]) ** (pick_season - current_season))
  end

  def request_trade_proposal(current_season, current_pick_index, draft_order)
    overall_pick_number = current_season * Game::PICKS_PER_ROUND + current_pick_index
    magic_prime = 19

    if (overall_pick_number % magic_prime) < (magic_prime * @personality[:trade][:frequency])
      my_picks = find_remaining_picks(draft_order, [@team.idx], current_season, current_pick_index)
      others = [0,1,2,3]
      others.delete(@team.idx)
      others_picks = find_remaining_picks(draft_order, others, current_season, current_pick_index)

      from_pick = my_picks.first # TODO allow the AI to trade future picks
      from_pick_value = pick_value(current_season, from_pick[:season], from_pick[:pick_index])
      greed_threshold = from_pick_value * (1 + @personality[:trade][:greed])

      # Look for a target that's more valuable than my pick but within my greed threshold
      to_pick = others_picks.find do |other_pick|
        # Don't bother proposing a trade within season
        next if (from_pick[:season] == other_pick[:season])

        to_pick_value = pick_value(current_season, other_pick[:season], other_pick[:pick_index])
        (to_pick_value > from_pick_value) && (to_pick_value <= greed_threshold)
      end

      if to_pick
        $logger.debug "Proposing trade which loses #{from_pick_value} and gains #{pick_value(current_season, to_pick[:season], to_pick[:pick_index])}"

        Trade.new to_pick[:team_index], to_pick[:season], to_pick[:pick_index],
                  from_pick[:team_index], from_pick[:season], from_pick[:pick_index]
      else
        nil # no appealing trades (or no possible trades)
      end
    else
      nil
    end
  end

  def accept_trade?(season, pick_index, draft_order, trade)
    lost_value = pick_value(season, trade.to_season, trade.to_pick_index)
    gained_value = pick_value(season, trade.from_season, trade.from_pick_index)
    $logger.debug "Evaluating trade which loses #{lost_value} and gains #{gained_value}"
    gained_value > lost_value
  end

  def make_move(match)
    # Strategic TODOs
    # * don't pass if you're the opener and you have more than two cards
    # * in general, AI passes too much early on. pass less if you have more cards?
    # * Size opponent's play (min, max, mean) based on knowledge of their hand and # of cards played
    # * Play until your total exceeds your best estimate of their total, and no more
    # * don't play all of your cards in a semifinal (unless the other side of the bracket already did and you're the home team)
    # * pass rate paramaterized on cards played / remaining
    # * if the opponent has passed, play the smallest card you can to win

    # Calculate some hand metrics
    opponent_starting_hand = match.opponent_starting_hand(@team)
    opponent_card_count = match.opponent_card_count(@team)

    # TODO this is unused, find something to do with it
    #opponent_hand_estimates = Array.new(100) { opponent_starting_hand.shuffle.first(opponent_card_count).reduce(&:+) || 0 }
    #opponent_hand_estimate = opponent_hand_estimates.reduce(&:+).to_f / opponent_hand_estimates.size.to_f

    # TODO much of this context is cachable from play to play
    metrics = {
      worst_current_opponent_score: opponent_starting_hand.sort.first(opponent_card_count).reduce(&:+) || 0,
      best_current_opponent_score: opponent_starting_hand.sort.last(opponent_card_count).reduce(&:+) || 0,
      #estimated_current_opponent_score: opponent_hand_estimate,
      best_possible_opponent_score: opponent_starting_hand.reduce(&:+) || 0,
      my_score: match.my_score(@team),
      my_best_possible_score: match.starting_hand(@team).reduce(&:+) || 0,
    }

    if match.opponent_has_passed(@team)
      metrics[:best_possible_opponent_score] = metrics[:best_current_opponent_score]
    end

    $logger.debug "hand analysis", metrics

    match_personality = @personality[match.stage]

    score_ratio = metrics[:my_best_possible_score].to_f / (metrics[:best_possible_opponent_score].to_f + 1.0)
    aggression = match_personality[:aggression] * (score_ratio ** match_personality[:score_ratio_exponent])
    if match.is_home_team?(@team)
      aggression *= match_personality[:home_aggression_bonus]
    end

    $logger.debug "Aggression for this play is: #{aggression}"

    hand_load_factor = @team.roster.size.to_f / 10.0
    effective_pass_rate = match_personality[:pass_rate] / (aggression * hand_load_factor)
    $logger.debug "Current pass rate is: #{effective_pass_rate}"

    needed_for_guaranteed_lead = metrics[:best_current_opponent_score] - metrics[:my_score] + 1 # TODO include home adv here
    wasted_cards = @team.roster.sort[0...-2]
    leapfrog_cards = wasted_cards.find_all { |w| w > needed_for_guaranteed_lead }
    $logger.debug("leapfrog?", needed_for_guaranteed_lead: needed_for_guaranteed_lead, wasted_cards: wasted_cards, leapfrog_cards: leapfrog_cards)

    if metrics[:my_score] > metrics[:best_possible_opponent_score]
      $logger.debug "Victory is guaranteed, passing"
      :pass

    elsif metrics[:my_best_possible_score] < metrics[:worst_current_opponent_score]
      $logger.debug "No win situation, throwing off"
      throw_off_or_pass

    elsif (needed_for_guaranteed_lead > 0) && !leapfrog_cards.empty?
      # We can take the lead by playing off a card that we would lose anyway in the offseason, so do it
      # This might not be optimal but it's better than the AI's current behavior
      # TODO but in most cases, still too conservative
      $logger.debug "can take the lead with any of #{leapfrog_cards}, will play one of them"
      play_card_with_aggression(aggression, card_set: leapfrog_cards)

    elsif (match.stage == :final) && (@team.roster.size > 2)
      # TODO No point in passing, *but* I maybe shouldn't be playing by best cards in this mode
      $logger.debug "Will never pass in the final with more than two cards left"
      play_card_with_aggression(aggression)
    elsif effective_pass_rate > 0.5
      :pass
    else
      play_card_with_aggression(aggression)
    end
  end
end
