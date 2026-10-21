import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../widgets/chunky.dart';
import '../widgets/team_logo.dart';

class TeamScreen extends StatelessWidget {
  const TeamScreen({super.key, required this.data, required this.team});

  final RankingsData data;
  final Team team;

  @override
  Widget build(BuildContext context) {
    final games = data.gamesFor(team.id);
    final dates = MaterialLocalizations.of(context);

    return Scaffold(
      backgroundColor: Palette.blue,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Tooltip(
                    message: 'Back',
                    child: Chunky(
                      radius: 999,
                      color: Palette.yellow,
                      padding: const EdgeInsets.all(8),
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const Icon(Icons.arrow_back_rounded, color: Palette.ink),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Chunky(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      TeamLogo(team: team, size: 72),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(team.name, style: display(30)),
                            if (team.hometown.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(team.hometown, style: body(15, weight: 800, color: Palette.ink.withValues(alpha: 0.7))),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (team.level != null && team.levelRank != null)
                      _Stat(
                          label: '${ageLabel(team.age)} ${levelLabel(team.level!)} rank'.trim(),
                          value: '#${team.levelRank}',
                          color: Palette.yellow)
                    else
                      _Stat(
                          label: 'Class',
                          value: team.level != null
                              ? levelLabel(team.level!)
                              : team.sources.any((s) => s.ageClass.toLowerCase().contains('open'))
                                  ? 'Open'
                                  : 'None',
                          color: Palette.yellow),
                    _Stat(
                        label: team.age == null ? 'Rank' : 'All ${ageLabel(team.age)} rank',
                        value: team.rank == null ? 'Not ranked' : '#${team.rank}',
                        color: Palette.pink),
                    _Stat(label: 'Record', value: team.record, color: Palette.green),
                    if (team.classRecords.isNotEmpty) _ClassRecords(team: team),
                    _Stat(label: 'Rating', value: team.rating.toStringAsFixed(3)),
                    _Stat(label: 'Schedule strength', value: team.sos.toStringAsFixed(3)),
                    _Stat(
                      label: 'Runs',
                      value: '${team.runsFor}-${team.runsAgainst} '
                          '(${team.runDiff >= 0 ? '+' : ''}${team.runDiff})',
                      color: Palette.orange,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in team.sources)
                      Chunky(
                        radius: 999,
                        shadow: 2,
                        border: 2,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        onTap: s.url.isEmpty ? null : () => launchUrl(Uri.parse(s.url)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (s.url.isNotEmpty) ...[
                            const Icon(Icons.open_in_new, size: 15, color: Palette.ink),
                            const SizedBox(width: 6),
                          ],
                          Text('${s.label}${s.name != team.name ? ': ${s.name}' : ''}', style: body(13, weight: 800)),
                        ]),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Shout('Games (${games.length})', size: 30),
                const SizedBox(height: 12),
                for (final g in games) ...[
                  _GameTile(data: data, team: team, game: g, dates: dates),
                  const SizedBox(height: 10),
                ],
              ],
            ),
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
    final (:opponent, :us, :them) = game.from(team.id);
    final opp = data.teamsById[opponent];
    final (letter, color) = us > them
        ? ('W', Palette.green)
        : us < them
            ? ('L', Palette.pink)
            : ('T', Palette.sky);
    // Name the opponent's age only when it differs, e.g. a team playing up.
    final oppAge = opp?.age != null && opp!.age != team.age ? ' ${ageLabel(opp.age)}' : '';
    final oppLabel = [
      if (opp?.levelRank != null) '#${opp!.levelRank}$oppAge ${levelLabel(opp.level!)}'
      else if (opp?.rank != null) '#${opp!.rank}$oppAge',
      opp?.name ?? 'Unknown team',
      if (opp != null && opp.state.isNotEmpty && opp.state != data.state) '(${opp.state})',
    ].join(' ');

    return Chunky(
      padding: const EdgeInsets.all(10),
      shadow: 3,
      onTap: opp == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TeamScreen(data: data, team: opp),
              )),
      child: Row(
        children: [
          // The result and score lead the card, big enough to read at a glance.
          Chunky(
            color: color,
            radius: 12,
            shadow: 0,
            border: 2.5,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: SizedBox(
              width: 64,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(letter, style: display(15)),
                  FittedBox(child: Text('$us–$them', style: display(26))),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('vs $oppLabel', style: display(17)),
                const SizedBox(height: 2),
                Text('${dates.formatShortDate(game.date)} · ${game.event} · ${sourceLabel(game.source)}',
                    style: body(12, weight: 700, color: Palette.ink.withValues(alpha: 0.65))),
              ],
            ),
          ),
          if (opp != null) ...[
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TeamLogo(team: opp, size: 30),
                const SizedBox(height: 4),
                Text(opp.record, style: body(12, weight: 800, color: Palette.ink.withValues(alpha: 0.65))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One chip with [team]'s record against each class it has played, AA
/// first: "vs AA 5-2", "vs AAA 1-3".
class _ClassRecords extends StatelessWidget {
  const _ClassRecords({required this.team});
  final Team team;

  static const _order = ['AA', 'AAA', 'Majors', 'Other'];

  @override
  Widget build(BuildContext context) {
    int place(String cls) => _order.contains(cls) ? _order.indexOf(cls) : _order.length;
    final classes = team.classRecords.keys.toList()..sort((a, b) => place(a).compareTo(place(b)));
    return Chunky(
      color: Palette.green,
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Wrap(
        spacing: 18,
        runSpacing: 6,
        children: [
          for (final cls in classes)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('vs ${cls == 'Other' ? cls : levelLabel(cls)}', style: body(12, weight: 900)),
                Text(_record(team.classRecords[cls]!), style: display(24)),
              ],
            ),
        ],
      ),
    );
  }

  static String _record(({int wins, int losses, int ties}) r) =>
      r.ties > 0 ? '${r.wins}-${r.losses}-${r.ties}' : '${r.wins}-${r.losses}';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color = Palette.white});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Chunky(
        color: color,
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: body(12, weight: 900)),
            Text(value, style: display(24)),
          ],
        ),
      );
}
