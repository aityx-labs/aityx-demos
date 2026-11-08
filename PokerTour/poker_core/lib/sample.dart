/// A sample situation to try a strategy on: on the button, facing a bet
/// on the flop with top pair (A♥ K♦ on K♠ 7♣ 2♦, 40 to call into a pot of
/// 120, 78% equity). The app's editor tries rules on it, and the server
/// checks a strategy entered in the tour with it before accepting it.
library;

const sampleSituation = <String, Object?>{
  'street': 'flop',
  'position': 'late',
  'hole': ['Ah', 'Kd'],
  'board': ['Ks', '7c', '2d'],
  'hand': 'strong',
  'made_hand': 'pair',
  'flush_draw': false,
  'straight_draw': 'none',
  'equity': 0.78,
  'pot': 120,
  'current_bet': 40,
  'to_call': 40,
  'pot_odds': 0.25,
  'can_check': false,
  'can_raise': true,
  'raises': 1,
  'stack': 960,
  'big_blind': 10,
  'stack_bb': 96,
  'min_raise': 80,
  'max_raise': 1000,
  'players_in_hand': 3,
  'players_after': 0,
  'random': 0.42,
};

/// What the sample is, for people.
const sampleSituationLabel =
    'A♥ K♦ on K♠ 7♣ 2♦, top pair, 40 to call into a pot of 120, 78% equity';
