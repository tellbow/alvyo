import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../l10n/app_localizations.dart';

/// Public transport between two stops on a day, leaving after or arriving
/// before a time, as on the website's journeys.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key, required this.api, required this.from, required this.to, required this.day});
  final Api api;
  final Place from, to;
  final DateTime day;

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  late var _time = _startTime();
  var _arrive = false;
  Future<List<Trip>>? _trips;

  /// From now on today; at 8 on another day.
  TimeOfDay _startTime() {
    final now = DateTime.now();
    final today = widget.day.year == now.year && widget.day.month == now.month && widget.day.day == now.day;
    return today ? TimeOfDay.fromDateTime(now) : const TimeOfDay(hour: 8, minute: 0);
  }

  @override
  void initState() {
    super.initState();
    _search();
  }

  void _search() {
    final hhmm = '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
    setState(() {
      _trips = widget.api.connections(widget.from.ref, widget.to.ref, widget.day, time: hhmm, arrive: _arrive);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: Text(t.connectionsShow)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${widget.from.name} → ${widget.to.name}', style: theme.textTheme.titleMedium),
          Text(formatDate(widget.day), style: muted),
          const SizedBox(height: 12),
          Row(
            spacing: 8,
            children: [
              SegmentedButton<bool>(
                key: const Key('connections-mode'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: false, label: Text(t.connectionsDepart)),
                  ButtonSegment(value: true, label: Text(t.connectionsArrive)),
                ],
                selected: {_arrive},
                onSelectionChanged: (s) {
                  _arrive = s.first;
                  _search();
                },
              ),
              OutlinedButton(
                key: const Key('connections-time'),
                onPressed: () async {
                  final picked = await showTimePicker(context: context, initialTime: _time);
                  if (picked == null) return;
                  _time = picked;
                  _search();
                },
                child: Text(_time.format(context)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder(
            future: _trips,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                final e = snap.error;
                return Text(e is ApiException && e.status == 429 ? t.shareRate : t.connectionsUnavailable);
              }
              final trips = snap.data!;
              if (trips.isEmpty) return Text(key: const Key('connections-none'), t.connectionsNone);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, trip) in trips.indexed) TripCard(key: Key('trip-$i'), trip: trip),
                  const SizedBox(height: 8),
                  Text(t.connectionsSource, style: theme.textTheme.bodySmall?.merge(muted)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A connection: its times, rides and walks; [onTap] chooses it (drawn on
/// the map when [selected]).
class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.trip, this.selected = false, this.onTap});
  final Trip trip;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: theme.colorScheme.primary, width: 2),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${formatTime(trip.start)} → ${formatTime(trip.end)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(
                      text:
                          ' · ${trip.end.difference(trip.start).inMinutes} min · '
                          '${t.connectionsTransfers(trip.transfers)}',
                      style: muted,
                    ),
                  ],
                ),
              ),
              for (final leg in trip.legs)
                if (leg.ride && leg.departure != null)
                  Text.rich(
                    TextSpan(
                      style: muted,
                      children: [
                        TextSpan(text: '${formatTime(leg.departure!)} '),
                        TextSpan(
                          text: leg.line,
                          style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
                        ),
                        TextSpan(text: ' ${leg.from} → ${leg.to}'),
                        if (leg.platform.isNotEmpty) TextSpan(text: ' · ${t.connectionsPlatform(leg.platform)}'),
                        if (leg.delayMin > 0)
                          TextSpan(
                            text: ' +${leg.delayMin}′',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                      ],
                    ),
                  )
                else if (!leg.ride)
                  Text(t.connectionsWalk(leg.walkMin), style: muted),
            ],
          ),
        ),
      ),
    );
  }
}
