import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'settings.dart';

/// What the planner's points and handles mean and what to do with them
/// (feedback issue 88): open until hidden, then a button brings it back.
class PlannerHelp extends StatelessWidget {
  const PlannerHelp({super.key});

  /// The points' colours on the map.
  static const start = Color(0xff15803d), via = Color(0xff7e22ce), end = Color(0xffb91c1c);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final settings = AppSettings.instance;
    return ValueListenableBuilder(
      valueListenable: settings.plannerHelpHidden,
      builder: (context, hidden, _) {
        if (hidden) {
          return Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('planner-help-open'),
              onPressed: () => settings.setPlannerHelpHidden(false),
              icon: const Icon(Icons.help_outline),
              label: Text(t.plannerHelpTitle),
            ),
          );
        }
        Widget dot(Color fill, Color border, double width) => Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: width),
          ),
        );
        Widget row(Widget? lead, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(width: 24, child: lead ?? const Text('•', textAlign: TextAlign.center)),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
            ],
          ),
        );
        return Card(
          key: const Key('planner-help'),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 4, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(t.plannerHelpTitle, style: Theme.of(context).textTheme.titleSmall)),
                    TextButton(
                      key: const Key('planner-help-hide'),
                      onPressed: () => settings.setPlannerHelpHidden(true),
                      child: Text(t.plannerHelpHide),
                    ),
                  ],
                ),
                row(dot(start, Colors.white, 2), t.plannerHelpStart),
                row(dot(via, Colors.white, 2), t.plannerHelpVia),
                row(dot(end, Colors.white, 2), t.plannerHelpEnd),
                row(dot(Colors.white, via, 3), t.plannerHelpMidpoint),
                const SizedBox(height: 4),
                row(null, t.plannerHelpTap),
                row(null, t.plannerHelpDrag),
                row(null, t.plannerHelpRound),
              ],
            ),
          ),
        );
      },
    );
  }
}
