import 'package:flutter/material.dart';

/// An entry of a list as a card, as on the website.
class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Card(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5), clipBehavior: Clip.antiAlias, child: child);
}
