import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n/app_localizations.dart';
import 'place_layer.dart';
import 'screens/wide.dart';

/// A field for finding places, names and addresses (`GET /places/search`).
/// A tap opens the search on a page of its own, the results right below the
/// field: in a planner's panel they would lie under the keyboard. The place
/// picked there goes to [onPick].
class PlaceSearch extends StatelessWidget {
  const PlaceSearch({super.key, required this.api, required this.onPick, this.label, this.near});
  final Api api;
  final ValueChanged<FoundPlace> onPick;

  /// The field's hint; «Ort suchen …» if none.
  final String? label;

  /// E.g. the map centre: among equally good matches, the nearest first.
  final LonLat? Function()? near;

  Future<void> _open(BuildContext context) async {
    final picked = await Navigator.of(context).push(
      MaterialPageRoute<FoundPlace>(
        fullscreenDialog: true,
        builder: (_) => _SearchPage(api: api, label: label, near: near?.call()),
      ),
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('place-search-open'),
    readOnly: true,
    onTap: () => _open(context),
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.search),
      hintText: label ?? AppLocalizations.of(context).placeSearch,
    ),
  );
}

class _SearchPage extends StatefulWidget {
  const _SearchPage({required this.api, this.label, this.near});
  final Api api;
  final String? label;
  final LonLat? near;

  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
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
        final found = await widget.api.searchPlaces(q, near: widget.near);
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

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const Key('place-search'),
          autofocus: true,
          onChanged: _changed,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(border: InputBorder.none, hintText: widget.label ?? t.placeSearch),
        ),
      ),
      body: Readable(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (_failed)
              Padding(padding: const EdgeInsets.all(16), child: Text(t.errorServer))
            else if (results != null && results.isEmpty)
              Padding(padding: const EdgeInsets.all(16), child: Text(t.placeNothingFound))
            else if (results != null)
              for (final (i, p) in results.indexed)
                ListTile(
                  key: Key('place-result-$i'),
                  title: Text(p.name),
                  subtitle: Text(placeKindText(t, p.kind, p.detail)),
                  onTap: () {
                    _timer?.cancel();
                    _asked++;
                    Navigator.of(context).pop(p);
                  },
                ),
          ],
        ),
      ),
    );
  }
}
