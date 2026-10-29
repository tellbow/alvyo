import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/app_localizations.dart';
import 'journey_plan_screen.dart';
import 'planner_screen.dart';
import 'reach_screen.dart';
import 'tab_header.dart';
import 'wide.dart';

/// The kinds of planning.
enum PlanMode { day, multi, reach }

/// Planen (requirement 69): one place for a day's route, a journey of
/// several days and how far one gets. «Importieren» is in the profile.
class PlanTab extends StatefulWidget {
  const PlanTab({super.key, required this.api, this.onSaved, this.modes});
  final Api api;

  /// A route or journey was saved: the tours load again.
  final VoidCallback? onSaved;

  /// For tests: stands in for the planning screens (MapLibre).
  final Widget Function(PlanMode mode, VoidCallback saved)? modes;

  @override
  State<PlanTab> createState() => PlanTabState();
}

class PlanTabState extends State<PlanTab> {
  PlanMode _mode = PlanMode.day;

  /// Counts the plans: a new one after each save.
  int _plan = 0;

  /// Shows a mode (from Entdecken).
  void show(PlanMode mode) => setState(() => _mode = mode);

  void _saved() {
    widget.onSaved?.call();
    if (mounted) setState(() => _plan++);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final key = ValueKey('${_mode.name}-$_plan');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabHeader(t.barPlan),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          // On a wide screen above the panel, as wide as it.
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: isWide(context) ? panelWidth - 32 : double.infinity,
              child: SegmentedButton<PlanMode>(
                key: const Key('plan-mode'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: PlanMode.day,
                    label: Text(t.planDay, key: const Key('plan-mode-day')),
                  ),
                  ButtonSegment(
                    value: PlanMode.multi,
                    label: Text(t.planMulti, key: const Key('plan-mode-multi')),
                  ),
                  ButtonSegment(
                    value: PlanMode.reach,
                    label: Text(t.planReach, key: const Key('plan-mode-reach')),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() => _mode = v.first),
              ),
            ),
          ),
        ),
        Expanded(
          // Above the floating bar: the home screen's Scaffold passes its
          // height (with the phone's bottom edge) as padding.
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child:
                  widget.modes?.call(_mode, _saved) ??
                  switch (_mode) {
                    PlanMode.day => PlannerScreen(key: key, api: widget.api, embedded: true, onSaved: _saved),
                    PlanMode.multi => JourneyPlanScreen(key: key, api: widget.api, embedded: true, onSaved: _saved),
                    // A route planned from there opens on top; the reach stays.
                    PlanMode.reach => ReachScreen(key: key, api: widget.api, embedded: true, onSaved: widget.onSaved),
                  },
            ),
          ),
        ),
      ],
    );
  }
}
