import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n/app_localizations.dart';
import 'place_layer.dart';

/// A search field for places, names and addresses (`GET /places/search`)
/// with the results below it; a tap on one hands it to [onPick] and clears
/// the field.
class PlaceSearch extends StatefulWidget {
  const PlaceSearch({super.key, required this.api, required this.onPick, this.label, this.near});
  final Api api;
  final ValueChanged<FoundPlace> onPick;

  /// The field's hint; «Ort suchen …» if none.
  final String? label;

  /// E.g. the map centre: among equally good matches, the nearest first.
  final LonLat? Function()? near;

  @override
  State<PlaceSearch> createState() => _PlaceSearchState();
}

class _PlaceSearchState extends State<PlaceSearch> {
  final _text = TextEditingController();
  Timer? _timer;

  /// Counts the searches: only the latest answer is shown.
  int _asked = 0;

  /// Null while nothing is searched for.
  List<FoundPlace>? _results;
  bool _failed = false;

  void _changed(String value) {
    _timer?.cancel();
    final q = value.trim();
    final asked = ++_asked;
    if (q.length < 2) {
      setState(() {
        _results = null;
        _failed = false;
      });
      return;
    }
    _timer = Timer(const Duration(milliseconds: 250), () async {
      try {
        final found = await widget.api.searchPlaces(q, near: widget.near?.call());
        if (!mounted || asked != _asked) return;
        setState(() {
          _results = found;
          _failed = false;
        });
      } on Object {
        if (!mounted || asked != _asked) return;
        setState(() {
          _results = null;
          _failed = true;
        });
      }
    });
  }

  void _pick(FoundPlace p) {
    _timer?.cancel();
    _asked++;
    _text.clear();
    setState(() => _results = null);
    widget.onPick(p);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final results = _results;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('place-search'),
          controller: _text,
          onChanged: _changed,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: widget.label ?? t.placeSearch),
        ),
        if (_failed)
          Padding(padding: const EdgeInsets.all(8), child: Text(t.errorServer))
        else if (results != null && results.isEmpty)
          Padding(padding: const EdgeInsets.all(8), child: Text(t.placeNothingFound))
        else if (results != null)
          for (final (i, p) in results.indexed)
            ListTile(
              key: Key('place-result-$i'),
              dense: true,
              title: Text(p.name),
              subtitle: Text(placeKindText(t, p.kind, p.detail)),
              onTap: () => _pick(p),
            ),
      ],
    );
  }
}
