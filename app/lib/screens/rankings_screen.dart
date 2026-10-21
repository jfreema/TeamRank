import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../widgets/chunky.dart';
import '../widgets/team_logo.dart';
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
  final _search = TextEditingController();

  /// Waits for a pause in typing before filtering; emptying the box resets at once.
  Timer? _searchDelay;

  void _onSearch(String v) {
    _searchDelay?.cancel();
    if (v.trim().isEmpty) {
      setState(() => _query = '');
    } else {
      _searchDelay = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _query = v);
      });
    }
  }

  @override
  void dispose() {
    _searchDelay?.cancel();
    _search.dispose();
    super.dispose();
  }
  String? _source;
  int _minGames = 0;

  /// `AA`, `AAA`, or null for everyone.
  String? _level;

  /// The age group shown; null until the data loads, then 12U if present.
  int? _age;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.blue,
      body: FutureBuilder<RankingsData>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) {
            return _Message(
              icon: Icons.cloud_off,
              text: 'Could not load rankings.\n${snap.error}',
              action: Pill(
                label: 'Try again',
                selected: true,
                onTap: () => setState(() => _data = widget.loader()),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: Palette.yellow));
          }
          return _buildList(context, snap.data!);
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, RankingsData data) {
    final age = _age ??
        (data.ages.contains(14) ? 14 : (data.ages.isEmpty ? null : data.ages.last));
    final q = _query.trim().toLowerCase();
    final teams = data.ranked.where((t) {
      if (t.age != age) return false;
      if (_level != null && t.level != _level) return false;
      if (t.games < _minGames) return false;
      if (_source != null && !t.sources.any((s) => s.source == _source)) return false;
      if (q.isEmpty) return true;
      return t.name.toLowerCase().contains(q) || t.city.toLowerCase().contains(q);
    }).toList();
    if (_level != null) {
      teams.sort((a, b) => (a.levelRank ?? 1 << 30).compareTo(b.levelRank ?? 1 << 30));
    }

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header(data: data, age: age)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Chunky(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sized so 10U to 14U fit on one line on a phone.
                        Wrap(
                          spacing: 5,
                          runSpacing: 8,
                          children: [
                            for (final a in data.ages)
                              Pill(
                                label: ageLabel(a),
                                size: 18,
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                                selected: age == a,
                                onTap: () => setState(() {
                                  _age = a;
                                  _level = null; // each age opens on All
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final (value, label) in [
                              (null, 'All'),
                              ('AA', 'AA'),
                              ('AAA', 'AAA'),
                              ('Majors', 'Majors'),
                            ])
                              Pill(
                                label: label,
                                color: Palette.pink,
                                selected: _level == value,
                                onTap: () => setState(() => _level = value),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _search,
                          style: body(16),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search, color: Palette.ink),
                            // Shown as soon as there is text, before the search runs.
                            suffixIcon: ListenableBuilder(
                              listenable: _search,
                              builder: (context, _) => _search.text.isEmpty
                                  ? const SizedBox.shrink()
                                  : IconButton(
                                      tooltip: 'Clear search',
                                      icon: const Icon(Icons.close_rounded, color: Palette.ink),
                                      onPressed: () {
                                        _search.clear();
                                        _onSearch('');
                                      },
                                    ),
                            ),
                            hintText: 'Search team or town',
                            hintStyle: body(16, weight: 600, color: Palette.ink.withValues(alpha: 0.5)),
                            filled: true,
                            fillColor: Palette.sky,
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Palette.ink, width: 2.5),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Palette.ink, width: 2.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Palette.blue, width: 3),
                            ),
                          ),
                          onChanged: _onSearch,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final (value, label) in [
                              (null, 'All orgs'),
                              ('otc', 'OTC'),
                              ('2d', '2D'),
                              ('gs', 'Grand Slam'),
                              ('uacs', 'UACS'),
                            ])
                              Pill(
                                label: label,
                                size: 13,
                                color: Palette.orange,
                                selected: _source == value,
                                onTap: () => setState(() => _source = value),
                              ),
                            const SizedBox(width: 6),
                            for (final (value, label) in [(0, 'Any games'), (6, '6+ games')])
                              Pill(
                                label: label,
                                size: 13,
                                color: Palette.green,
                                selected: _minGames == value,
                                onTap: () => setState(() => _minGames = value),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (teams.isEmpty)
                const SliverToBoxAdapter(
                  child: _Message(icon: Icons.search_off, text: 'No teams match.'),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverList.separated(
                  itemCount: teams.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _TeamRow(
                    key: ValueKey(teams[i].id),
                    team: teams[i],
                    showLevel: _level == null,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => TeamScreen(data: data, team: teams[i]),
                    )),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.data, required this.age});
  final RankingsData data;
  final int? age;

  @override
  Widget build(BuildContext context) {
    final updated = MaterialLocalizations.of(context).formatMediumDate(data.generatedAt);
    final count = data.ranked.where((x) => x.age == age).length;
    final narrow = MediaQuery.sizeOf(context).width < 420;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Shout('TEAMRANK', size: narrow ? 44 : 60),
                    const SizedBox(height: 8),
                    const Sticker('LOUISIANA BASEBALL RANKINGS'),
                  ],
                ),
              ),
              Tooltip(
                message: 'How rankings work',
                child: Chunky(
                  radius: 999,
                  padding: const EdgeInsets.all(8),
                  color: Palette.yellow,
                  onTap: () => showAboutRankings(context),
                  child: const Icon(Icons.question_mark_rounded, color: Palette.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('${data.season} season · ${['$count Louisiana', if (age != null) ageLabel(age), 'teams'].join(' ')}',
              style: body(16, weight: 900, color: Palette.white)),
          const SizedBox(height: 2),
          Text(
            'Updated $updated · ${data.sources.entries.where((e) => e.value.games > 0).map((e) => '${sourceLabel(e.key)}: ${e.value.games} games').join(' · ')}',
            style: body(13, weight: 600, color: Palette.white.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({super.key, required this.team, required this.onTap, required this.showLevel});
  final Team team;

  /// On the combined list, show ranks within the age and each team's level.
  final bool showLevel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 600;
    final badge = width < 420 ? 38.0 : 46.0;
    final rank = showLevel ? team.rank : team.levelRank;
    return Chunky(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      child: Row(
        children: [
          Chunky(
            color: rankColor(rank),
            radius: 999,
            shadow: 0,
            border: 2.5,
            padding: EdgeInsets.zero,
            child: SizedBox(
              width: badge,
              height: badge,
              child: Center(child: Text('$rank', style: display(badge * (rank != null && rank > 99 ? 0.36 : 0.48)))),
            ),
          ),
          const SizedBox(width: 10),
          TeamLogo(team: team, size: badge - 4),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(team.name, style: display(19), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  [
                    team.hometown,
                    if (showLevel && team.level != null) levelLabel(team.level!),
                    team.sources.map((s) => s.source.toUpperCase()).toSet().join(' + '),
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: body(13, weight: 700, color: Palette.ink.withValues(alpha: 0.7)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Number(label: 'W-L', value: team.record),
          if (wide) ...[
            const SizedBox(width: 14),
            Tooltip(
              message: 'Strength of schedule: average rating of opponents',
              child: _Number(label: 'SCHED', value: team.sos.toStringAsFixed(3)),
            ),
          ],
          const SizedBox(width: 14),
          _Number(label: 'RATING', value: (showLevel ? team.rating : team.levelRating ?? team.rating).toStringAsFixed(3), highlight: true),
        ],
      ),
    );
  }
}

class _Number extends StatelessWidget {
  const _Number({required this.label, required this.value, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: body(10, weight: 900, color: Palette.ink.withValues(alpha: 0.55))),
          Text(value,
              style: display(18, color: highlight ? Palette.blue : Palette.ink)
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      );
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
            Icon(icon, size: 44, color: Palette.white),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: body(17, weight: 800, color: Palette.white)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      );
}

void showAboutRankings(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Chunky(
          shadow: 6,
          radius: 22,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How rankings work', style: display(28)),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    'TeamRank rates every team with an algorithm built on game results '
                    'from OTC Sports, 2D Sports, Grand Slam and UACS events this season.\n\n'
                    'It weighs who you beat, how strong their schedule was, head-to-head '
                    'results and run differential. A close loss to a good team can help '
                    'your ranking more than beating a weak team, so playing strong '
                    'opponents pays off. Teams are listed by the age and class '
                    'they registered in, and only Louisiana teams are ranked.\n\n'
                    'Updated weekly.',
                    style: body(15, weight: 600),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: Pill(label: 'Got it', selected: true, onTap: () => Navigator.pop(context)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
