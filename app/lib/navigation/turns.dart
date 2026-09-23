import '../api.dart';
import 'tracker.dart';

/// Something to say: a turn [inM] metres ahead, a turn now, or the arrival.
class Prompt {
  const Prompt.ahead(Turn this.turn, int this.inM);
  const Prompt.now(Turn this.turn) : inM = null;
  const Prompt.arrived() : turn = null, inM = null;
  final Turn? turn;
  final int? inM;
}

/// Turn-by-turn guidance: each turn is announced once ahead of it and once
/// at it, then the arrival.
class TurnGuide {
  TurnGuide(this.turns);
  final List<Turn> turns;

  /// Announced this far ahead; closer turns, right after the previous one,
  /// only at the turn.
  static const aheadM = 100.0, minAheadM = 50.0;

  /// «Now» this far before the turn: some seconds at walking speed, with GPS
  /// lag.
  static const nowM = 20.0;

  final _said = <(int, bool)>{}; // (turn, now)
  var _arrived = false;

  /// The next turn after [doneM] metres, and how far it is.
  (Turn, double)? next(double doneM) {
    for (final t in turns) {
      if (t.alongM > doneM) return (t, t.alongM - doneM);
    }
    return null;
  }

  /// What to say at [p], if anything. Nothing while off the route.
  Prompt? prompt(Progress p) {
    if (p.offRoute) return null;
    if (p.arrived) {
      if (_arrived) return null;
      _arrived = true;
      return const Prompt.arrived();
    }
    final i = turns.indexWhere((t) => t.alongM > p.doneM);
    if (i < 0) return null;
    final d = turns[i].alongM - p.doneM;
    if (d <= nowM) return _said.add((i, true)) ? Prompt.now(turns[i]) : null;
    if (d <= aheadM && d >= minAheadM && _said.add((i, false))) {
      return Prompt.ahead(turns[i], (d / 10).round() * 10);
    }
    return null;
  }
}
