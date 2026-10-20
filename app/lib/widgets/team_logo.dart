import 'package:flutter/material.dart';

import '../models.dart';

/// The team's logo from its org's site, or its initials when there is none.
class TeamLogo extends StatelessWidget {
  const TeamLogo({super.key, required this.team, this.size = 36});

  final Team team;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = team.name
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty && !RegExp(r'^\d+u$', caseSensitive: false).hasMatch(w))
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    final fallback = CircleAvatar(
      radius: size / 2,
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      child: Text(initials, style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w600)),
    );
    final logo = team.logo;
    if (logo == null || logo.isEmpty) return fallback;
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        child: Image.network(
          logo,
          fit: BoxFit.contain,
          // The orgs' image hosts don't send CORS headers, so let the browser
          // draw these with a plain <img> element.
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }
}
