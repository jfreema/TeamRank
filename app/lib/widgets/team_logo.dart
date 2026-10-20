import 'package:flutter/material.dart';

import '../models.dart';
import 'chunky.dart';

/// The team's logo from its org's site, or its initials when there is none.
class TeamLogo extends StatelessWidget {
  const TeamLogo({super.key, required this.team, this.size = 36});

  final Team team;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = team.name
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty && !RegExp(r'^\d+u$', caseSensitive: false).hasMatch(w))
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    final ring = Border.all(color: Palette.ink, width: size >= 60 ? 3 : 2);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Palette.yellow, shape: BoxShape.circle, border: ring),
      child: Text(initials, style: display(size * 0.38)),
    );
    final logo = team.logo;
    if (logo == null || logo.isEmpty) return fallback;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: ring),
      child: ClipOval(
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
