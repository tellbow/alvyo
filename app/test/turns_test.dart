import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/api.dart';
import 'package:alvyo/navigation/tracker.dart';
import 'package:alvyo/navigation/turns.dart';

/// Progress [doneM] metres along a 1 km route.
Progress at(double doneM, {bool offRoute = false}) => Progress(
  doneM: doneM,
  remainingM: 1000 - doneM,
  remaining: Duration.zero,
  distanceToRouteM: offRoute ? 80 : 3,
  offRoute: offRoute,
  arrived: 1000 - doneM < 30,
  at: const [8, 46.5],
);

String describe(Prompt p) => switch (p) {
  Prompt(turn: null) => 'arrived',
  Prompt(turn: final t?, inM: final m?) => 'in $m m ${t.kind}',
  Prompt(turn: final t?) => 'now ${t.kind}',
};

void main() {
  const turns = [Turn(300, 'left'), Turn(330, 'right'), Turn(800, 'keep_right')];

  test('each turn ahead and at it, a close one only at it, then the arrival', () {
    final g = TurnGuide(turns);
    final said = <String>[];
    for (var d = 0.0; d <= 1000; d += 5) {
      if (g.prompt(at(d)) case final p?) said.add('${d.round()}: ${describe(p)}');
    }
    expect(said, [
      '200: in 100 m left',
      '280: now left',
      '310: now right', // 30 m after the left one: no «in 30 m»
      '700: in 100 m keep_right',
      '780: now keep_right',
      '975: arrived',
    ]);
  });

  test('nothing twice when the position jumps back and forth, nothing while off the route', () {
    final g = TurnGuide(turns);
    expect(describe(g.prompt(at(210))!), 'in 90 m left');
    expect(g.prompt(at(205)), isNull);
    expect(g.prompt(at(215)), isNull);
    expect(g.prompt(at(285, offRoute: true)), isNull);
    expect(describe(g.prompt(at(285))!), 'now left');
    expect(g.prompt(at(302)), isNull); // right is 28 m ahead: too close for «in», not yet «now»
    expect(g.prompt(at(299)), isNull); // back before the left one: said already
  });

  test('the next turn and how far', () {
    final g = TurnGuide(turns);
    expect(g.next(0), (turns[0], 300.0));
    expect(g.next(300), (turns[1], 30.0));
    expect(g.next(900), isNull);
    expect(TurnGuide(const []).next(0), isNull);
  });
}
