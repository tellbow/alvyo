import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alvyo/screens/plan_sheet.dart';
import 'package:alvyo/screens/wide.dart';

/// Stands in for a map: counts how often it is built anew.
class _Map extends StatefulWidget {
  const _Map();
  static var created = 0;

  @override
  State<_Map> createState() => _MapState();
}

class _MapState extends State<_Map> {
  @override
  void initState() {
    super.initState();
    _Map.created++;
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(key: Key('map'), color: Colors.green);
}

void main() {
  Future<void> size(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pump();
  }

  setUp(() => _Map.created = 0);

  testWidgets('MapSplit: the panel under the map on a phone, on its left on an iPad, the map kept', (tester) async {
    addTearDown(tester.view.reset);
    await size(tester, const Size(400, 800));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MapSplit(share: 0.5, map: _Map(), panel: Text('panel')),
        ),
      ),
    );
    final panel = find.byKey(const Key('map-panel'));
    expect(tester.getRect(panel), const Rect.fromLTWH(0, 400, 400, 400));
    expect(tester.getRect(find.byKey(const Key('map'))), const Rect.fromLTWH(0, 0, 400, 400));

    await size(tester, const Size(1180, 820));
    expect(tester.getRect(panel), const Rect.fromLTWH(0, 0, panelWidth, 820));
    expect(tester.getTopLeft(find.byKey(const Key('map'))).dx, greaterThan(panelWidth));
    expect(_Map.created, 1);
  });

  testWidgets('MapSplit without a phone share: the panel alone on a phone', (tester) async {
    addTearDown(tester.view.reset);
    await size(tester, const Size(400, 800));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MapSplit(map: _Map(), panel: Text('panel')),
        ),
      ),
    );
    expect(find.byKey(const Key('map')), findsNothing);
    await size(tester, const Size(1180, 820));
    expect(find.byKey(const Key('map')), findsOneWidget);
  });

  testWidgets('PlanSheet: pulled over the map on a phone, beside it on an iPad, the map kept', (tester) async {
    addTearDown(tester.view.reset);
    await size(tester, const Size(400, 800));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlanSheet(map: _Map(), panelKey: Key('panel'), children: [Text('points')]),
        ),
      ),
    );
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(tester.getRect(find.byKey(const Key('map'))), const Rect.fromLTWH(0, 0, 400, 800));
    expect(PlanSheet.cover(tester.element(find.text('points'))), PlanSheet.initial);

    await size(tester, const Size(1180, 820));
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(tester.getRect(find.byKey(const Key('panel'))), const Rect.fromLTWH(0, 0, panelWidth, 820));
    expect(tester.getRect(find.byKey(const Key('map'))), const Rect.fromLTWH(panelWidth, 0, 1180 - panelWidth, 820));
    expect(PlanSheet.cover(tester.element(find.text('points'))), 0);
    expect(_Map.created, 1);
  });

  testWidgets('Readable: at most 720 wide in the middle, as wide as the screen when off', (tester) async {
    addTearDown(tester.view.reset);
    await size(tester, const Size(1180, 820));
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Readable(child: SizedBox.expand(key: Key('on'))),
            ),
            Expanded(
              child: Readable(on: false, child: SizedBox.expand(key: Key('off'))),
            ),
          ],
        ),
      ),
    );
    expect(tester.getRect(find.byKey(const Key('on'))), const Rect.fromLTWH(230, 0, 720, 410));
    expect(tester.getSize(find.byKey(const Key('off'))).width, 1180);
  });
}
