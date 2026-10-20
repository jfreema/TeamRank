import 'package:flutter/material.dart';

import '../models.dart';
import 'team_screen.dart';

class RankingsScreen extends StatefulWidget {
  const RankingsScreen({super.key, required this.loader});

  final Future<RankingsData> Function() loader;

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  late Future<RankingsData> _data = widget.loader();
  String _query = '';
  String? _source;
  int _minGames = 0;

  /// `AA`, `AAA`, or null for everyone.
  String? _level = 'AA';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Louisiana 12U Rankings'),
        actions: [
          IconButton(
            tooltip: 'How rankings work',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutRankings(context),
          ),
        ],
      ),
      body: FutureBuilder<RankingsData>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) {
            return _Message(
              icon: Icons.cloud_off,
              text: 'Could not load rankings.\n${snap.error}',
              action: FilledButton(
                onPressed: () => setState(() => _data = widget.loader()),
                child: const Text('Try again'),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildList(context, snap.data!);
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, RankingsData data) {
    final q = _query.trim().toLowerCase();
    final teams = data.ranked.where((t) {
      if (_level != null && t.level != _level) return false;
      if (t.games < _minGames) return false;
      if (_source != null && !t.sources.any((s) => s.source == _source)) return false;
      if (q.isEmpty) return true;
      return t.name.toLowerCase().contains(q) || t.city.toLowerCase().contains(q);
    }).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header(data: data)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SegmentedButton<String?>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'AA', label: Text('AA')),
                    ButtonSegment(value: 'AAA', label: Text('AAA / Majors')),
                    ButtonSegment(value: null, label: Text('All')),
                  ],
                  selected: {_level},
                  onSelectionChanged: (v) => setState(() => _level = v.first),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search team or town',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (value, label) in [
                      (null, 'All orgs'),
                      ('otc', 'OTC'),
                      ('2d', '2D'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _source == value,
                        onSelected: (_) => setState(() => _source = value),
                      ),
                    const SizedBox(width: 8),
                    for (final (value, label) in [(0, 'Any games'), (3, '3+ games'), (6, '6+ games')])
                      ChoiceChip(
                        label: Text(label),
                        selected: _minGames == value,
                        onSelected: (_) => setState(() => _minGames = value),
                      ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: _ColumnHeader()),
            if (teams.isEmpty)
              const SliverToBoxAdapter(
                child: _Message(icon: Icons.search_off, text: 'No teams match.'),
              ),
            SliverList.separated(
              itemCount: teams.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _TeamRow(
                team: teams[i],
                showLevel: _level == null,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TeamScreen(data: data, team: teams[i]),
                )),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.data});
  final RankingsData data;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final updated = MaterialLocalizations.of(context).formatMediumDate(data.generatedAt);
    final sources = data.sources.entries
        .map((e) => '${sourceLabel(e.key)}: ${e.value.games} games')
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${data.season} season · ${data.ranked.length} Louisiana teams', style: t.titleMedium),
          const SizedBox(height: 4),
          Text('Updated $updated · $sources', style: t.bodySmall),
        ],
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    final wide = MediaQuery.sizeOf(context).width >= 600;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 44, child: Text('#', style: style)),
          Expanded(child: Text('Team', style: style)),
          SizedBox(width: 64, child: Text('Record', style: style, textAlign: TextAlign.end)),
          if (wide) SizedBox(width: 64, child: Text('Sched.', style: style, textAlign: TextAlign.end)),
          SizedBox(width: 64, child: Text('Rating', style: style, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team, required this.onTap, required this.showLevel});
  final Team team;

  /// On the combined list, show overall ranks and each team's level.
  final bool showLevel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 600;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text('${showLevel ? team.rank : team.levelRank}',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(team.name, style: t.bodyLarge, overflow: TextOverflow.ellipsis),
                  Text(
                    [
                      team.hometown,
                      if (showLevel && team.level != null) team.level!,
                      team.sources.map((s) => s.source.toUpperCase()).toSet().join(' + '),
                    ]
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    style: t.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: 64, child: Text(team.record, textAlign: TextAlign.end)),
            if (wide)
              SizedBox(
                width: 64,
                child: Tooltip(
                  message: 'Strength of schedule: average rating of opponents',
                  child: Text(team.sos.toStringAsFixed(3), textAlign: TextAlign.end),
                ),
              ),
            SizedBox(
              width: 64,
              child: Text(team.rating.toStringAsFixed(3),
                  textAlign: TextAlign.end, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      );
}

void showAboutRankings(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('How rankings work'),
      content: const SingleChildScrollView(
        child: Text(
          'Teams are ranked with the Colley Matrix method, which rates every team '
          'from its wins and losses and the strength of the teams it played.\n\n'
          'Beating a team that has beaten good teams moves you up a lot. Beating a '
          'team that rarely wins barely moves you. If A beats B and C beats A, C '
          'rates above A.\n\n'
          'Margin of victory does not count, so running up the score gains nothing. '
          'Ties count as half a win.\n\n'
          'Results come from 12U divisions at OTC Sports and 2D Sports events this '
          'season (August to July). Out-of-state opponents count toward ratings, '
          'but only Louisiana teams are ranked. A team listed by both orgs is '
          'combined into one entry, and games reported twice are counted once.\n\n'
          'AA and AAA / Majors teams are listed separately, based on the class each '
          'team registered in (A teams are listed with AA). All teams are still '
          'rated together in one pool, so when an AA team beats a AAA team, the '
          'win counts against AAA-level competition. "All" shows the overall order.\n\n'
          'Ratings center on 0.500. "Sched." is strength of schedule: the average '
          'rating of a team\'s opponents. Teams with only a few games are less '
          'certain, so use the games filter to hide them.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ),
  );
}
