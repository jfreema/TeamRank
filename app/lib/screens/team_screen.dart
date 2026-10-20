import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../widgets/team_logo.dart';

class TeamScreen extends StatelessWidget {
  const TeamScreen({super.key, required this.data, required this.team});

  final RankingsData data;
  final Team team;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final games = data.gamesFor(team.id);
    final dates = MaterialLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(team.name)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TeamLogo(team: team, size: 64),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(team.name, style: t.headlineSmall),
                              if (team.hometown.isNotEmpty) Text(team.hometown, style: t.titleSmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (team.level != null && team.levelRank != null)
                          _Stat(label: '${levelLabel(team.level!)} rank', value: '#${team.levelRank}'),
                        _Stat(label: 'Overall rank', value: team.rank == null ? 'Not ranked' : '#${team.rank}'),
                        _Stat(label: 'Record', value: team.record),
                        _Stat(label: 'Rating', value: team.rating.toStringAsFixed(3)),
                        _Stat(label: 'Schedule strength', value: team.sos.toStringAsFixed(3)),
                        _Stat(
                          label: 'Runs',
                          value: '${team.runsFor}-${team.runsAgainst} '
                              '(${team.runDiff >= 0 ? '+' : ''}${team.runDiff})',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final s in team.sources)
                          if (s.url.isNotEmpty)
                            ActionChip(
                              avatar: const Icon(Icons.open_in_new, size: 16),
                              label: Text('${s.label}${s.name != team.name ? ': ${s.name}' : ''}'),
                              onPressed: () => launchUrl(Uri.parse(s.url)),
                            )
                          else
                            Chip(label: Text('${s.label}: ${s.name}')),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Games (${games.length})', style: t.titleMedium),
              ),
              for (final g in games) _GameTile(data: data, team: team, game: g, dates: dates),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.data, required this.team, required this.game, required this.dates});

  final RankingsData data;
  final Team team;
  final GameResult game;
  final MaterialLocalizations dates;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (:opponent, :us, :them) = game.from(team.id);
    final opp = data.teamsById[opponent];
    final (letter, color) = us > them
        ? ('W', Colors.green.shade700)
        : us < them
            ? ('L', scheme.error)
            : ('T', scheme.outline);
    final oppLabel = [
      if (opp?.levelRank != null) '#${opp!.levelRank} ${opp.level}'
      else if (opp?.rank != null) '#${opp!.rank}',
      opp?.name ?? 'Unknown team',
      if (opp != null && opp.state.isNotEmpty && opp.state != data.state) '(${opp.state})',
    ].join(' ');

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        child: Text(letter),
      ),
      trailing: opp == null
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              Text(opp.record),
              const SizedBox(width: 12),
              TeamLogo(team: opp, size: 28),
            ]),
      title: Text('$us-$them vs $oppLabel'),
      subtitle: Text('${dates.formatShortDate(game.date)} · ${game.event} · ${sourceLabel(game.source)}'),
      onTap: opp == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TeamScreen(data: data, team: opp),
              )),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: t.labelSmall),
            Text(value, style: t.titleMedium),
          ],
        ),
      ),
    );
  }
}
