import 'colley.dart';
import 'identity.dart';
import 'model.dart';

/// Builds the JSON the app reads: Louisiana 12U teams ranked by Colley rating.
///
/// Ratings are computed over every 12U team in the data, including
/// out-of-state opponents, so a win over a strong Mississippi team still
/// counts. Only Louisiana teams get a rank.
/// How many games a win over a AAA / Majors team counts as.
const aaaWinWeight = 1.5;

({Map<String, dynamic> rankings, String review}) buildRankings({
  required List<SourceCache> caches,
  required Aliases aliases,
  required String season,
  required DateTime generatedAt,
  String state = 'LA',
}) {
  final sourceTeams = <String, SourceTeam>{
    for (final c in caches) ...c.teams,
  };
  final eventsOf = <String, Set<String>>{};
  for (final c in caches) {
    for (final g in c.games) {
      for (final k in [g.teamA, g.teamB]) {
        eventsOf.putIfAbsent(k, () => {}).add('${g.source}:${g.eventId}');
      }
    }
  }
  final grouping = groupTeams(sourceTeams.values, aliases, eventsOf: eventsOf);
  final groupOf = grouping.groupOf;

  final games = dedupeGames([
    for (final c in caches)
      for (final g in c.games)
        if (groupOf.containsKey(g.teamA) &&
            groupOf.containsKey(g.teamB) &&
            groupOf[g.teamA] != groupOf[g.teamB])
          g
  ], groupOf)
    ..sort((a, b) => a.date.compareTo(b.date));

  final ids = {for (final g in games) ...[groupOf[g.teamA]!, groupOf[g.teamB]!]}
      .toList()
    ..sort();
  final index = {for (var i = 0; i < ids.length; i++) ids[i]: i};

  final members = <String, List<SourceTeam>>{};
  for (final t in sourceTeams.values) {
    final id = groupOf[t.key];
    if (id != null) members.putIfAbsent(id, () => []).add(t);
  }

  // AA and AAA/Majors get their own lists, but the ratings behind them come
  // from one pool so games between the levels still count.
  String? levelFor(String id) {
    final list = members[id] ?? [];
    for (final t in list) {
      if (aliases.levels[t.key] case final l?) return l.toUpperCase();
    }
    final levels = list.map((t) => levelOf(t.ageClass)).whereType<String>().toSet();
    // A team listed at both levels plays up, so it goes with the higher one.
    return levels.contains('AAA') ? 'AAA' : (levels.isEmpty ? null : 'AA');
  }

  // A win over a AAA / Majors team counts extra ([aaaWinWeight] games).
  double weightOf(Game g) {
    if (g.scoreA == g.scoreB) return 1;
    final loser = g.scoreA > g.scoreB ? g.teamB : g.teamA;
    return levelFor(groupOf[loser]!) == 'AAA' ? aaaWinWeight : 1;
  }

  final ratings = colleyRatings(ids.length, [
    for (final g in games)
      Result(index[groupOf[g.teamA]]!, index[groupOf[g.teamB]]!, g.scoreA, g.scoreB,
          weight: weightOf(g))
  ]);

  final stats = {for (final id in ids) id: _Stats()};
  for (final g in games) {
    final a = groupOf[g.teamA]!, b = groupOf[g.teamB]!;
    stats[a]!.add(g.scoreA, g.scoreB, ratings[index[b]!]);
    stats[b]!.add(g.scoreB, g.scoreA, ratings[index[a]!]);
  }

  bool isHome(String id) =>
      (members[id] ?? []).any((t) => t.state.toUpperCase() == state);

  final ranked = ids.where(isHome).toList()
    ..sort((a, b) => ratings[index[b]!].compareTo(ratings[index[a]!]));

  // Each team is listed at the age it registered as, even when it plays up.
  // The ratings still come from one pool across ages.
  final divisionAges = <String, Map<int, int>>{};
  for (final g in games) {
    final age = ageOf(g.division);
    if (age == null) continue;
    for (final k in [g.teamA, g.teamB]) {
      final m = divisionAges.putIfAbsent(groupOf[k]!, () => {});
      m[age] = (m[age] ?? 0) + 1;
    }
  }
  int? ageFor(String id) {
    final list = members[id] ?? [];
    for (final t in list) {
      if (aliases.ages[t.key] case final a?) return a;
    }
    int? mostCommon(Iterable<int> ages) {
      final counts = <int, int>{};
      for (final a in ages) {
        counts[a] = (counts[a] ?? 0) + 1;
      }
      if (counts.isEmpty) return null;
      // Ties go to the younger age, since teams play up, not down.
      return (counts.entries.toList()
            ..sort((x, y) => y.value != x.value ? y.value - x.value : x.key - y.key))
          .first
          .key;
    }

    return mostCommon(list.map((t) => ageOf(t.ageClass)).whereType<int>()) ??
        mostCommon(divisionAges[id]?.entries.expand((e) => List.filled(e.value, e.key)) ?? []);
  }

  final ageOfTeam = {for (final id in ranked) id: ageFor(id)};
  // Only the covered ages are ranked; other ages still count as opponents.
  ranked.removeWhere((id) => !inAgeRange(ageOfTeam[id]));
  final levelOfTeam = {for (final id in ranked) id: levelFor(id)};
  final ageRank = <String, int>{};
  final levelRank = <String, int>{};
  final ageCounts = <int, Map<String, int>>{};
  for (final id in ranked) {
    final age = ageOfTeam[id];
    if (age == null) continue;
    final c = ageCounts.putIfAbsent(age, () => {'teams': 0, 'AA': 0, 'AAA': 0});
    ageRank[id] = c['teams'] = c['teams']! + 1;
    if (levelOfTeam[id] case final level?) levelRank[id] = c[level] = c[level]! + 1;
  }

  // Teams the app needs: every ranked team plus their opponents.
  final rankedSet = ranked.toSet();
  final homeGames = games
      .where((g) =>
          rankedSet.contains(groupOf[g.teamA]!) ||
          rankedSet.contains(groupOf[g.teamB]!))
      .toList();
  final needed = {
    ...ranked,
    for (final g in homeGames) ...[groupOf[g.teamA]!, groupOf[g.teamB]!]
  };

  String displayName(String id) {
    final list = members[id] ?? [];
    for (final t in list) {
      if (aliases.names[t.key] case final n?) return n;
    }
    // Prefer the source where the team played the most games.
    final counts = <String, int>{};
    for (final g in games) {
      for (final k in [g.teamA, g.teamB]) {
        if (groupOf[k] == id) counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    list.sort((a, b) => (counts[b.key] ?? 0).compareTo(counts[a.key] ?? 0));
    return list.isEmpty ? id : list.first.name;
  }

  final teamsOut = <Map<String, dynamic>>[];
  for (final id in needed.toList()
    ..sort((a, b) => ratings[index[b]!].compareTo(ratings[index[a]!]))) {
    final list = members[id] ?? [];
    final s = stats[id]!;
    final home = list.firstWhere((t) => t.city.isNotEmpty,
        orElse: () => list.isEmpty ? SourceTeam(key: id, name: id) : list.first);
    teamsOut.add({
      'id': id,
      'name': displayName(id),
      'city': _titleCase(home.city),
      'state': home.state,
      'age': ageOfTeam[id] ?? ageFor(id),
      'rank': ageRank[id],
      'level': levelOfTeam[id] ?? levelFor(id),
      'levelRank': levelRank[id],
      'rating': _round(ratings[index[id]!]),
      'sos': _round(s.sos),
      'wins': s.wins,
      'losses': s.losses,
      'ties': s.ties,
      'runsFor': s.runsFor,
      'runsAgainst': s.runsAgainst,
      'sources': [
        for (final t in list)
          {
            'key': t.key,
            'source': t.source,
            'name': t.name,
            'ageClass': t.ageClass,
            'url': t.url,
          }
      ],
      if (list.map((t) => t.logo).firstWhere((l) => l != null && l.isNotEmpty,
              orElse: () => null)
          case final logo?)
        'logo': logo,
    });
  }

  final rankings = {
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'season': season,
    'state': state,
    'method': 'colley',
    'aaaWinWeight': aaaWinWeight,
    'ages': {
      for (final a in ageCounts.keys.toList()..sort()) '$a': ageCounts[a],
    },
    'sources': {
      for (final c in caches)
        c.source: {
          'events': c.events.values.where((e) => e.games.isNotEmpty).length,
          'games': c.games.length,
        }
    },
    'teams': teamsOut,
    'games': [
      for (final g in homeGames)
        {
          'date': g.date,
          'source': g.source,
          'event': g.eventName,
          'division': g.division,
          'a': groupOf[g.teamA],
          'b': groupOf[g.teamB],
          'sa': g.scoreA,
          'sb': g.scoreB,
        }
    ],
  };
  final suggestions = <({List<String> keys, String reason})>[];
  final review = _review(grouping, sourceTeams, eventsOf, suggestions);
  // Possible duplicates the admin console offers to link, for teams on the site.
  rankings['suggestions'] = [
    for (final sg in suggestions)
      if (sg.keys.any((k) => isHome(groupOf[k] ?? '')))
        {
          'reason': sg.reason,
          'teams': [
            for (final k in sg.keys)
              {
                'key': k,
                'name': sourceTeams[k]!.name,
                'city': _titleCase(sourceTeams[k]!.city),
                'state': sourceTeams[k]!.state,
                'ageClass': sourceTeams[k]!.ageClass,
                'games': eventsOf[k]?.length ?? 0,
              }
          ],
        }
  ];
  return (rankings: rankings, review: review);
}

/// Removes games that were recorded more than once.
///
/// Each scraper already collapses the copies it sees (a game listed on both
/// teams' pages, or in two divisions' schedules for a crossover game). This
/// pass catches the rest: the same game reported by two sources for one
/// co-sanctioned event, or by two source listings of one team. Games match
/// when they share a date, the same two real teams and the same score. Within
/// one source, repeats of the same result are kept, since two teams can meet
/// twice in a weekend; across sources only the larger count is kept.
List<Game> dedupeGames(List<Game> games, Map<String, String> groupOf) {
  final perKey = <String, Map<String, List<Game>>>{};
  for (final g in games) {
    final a = groupOf[g.teamA]!, b = groupOf[g.teamB]!;
    final key = a.compareTo(b) <= 0
        ? '${g.date}|$a|$b|${g.scoreA}|${g.scoreB}'
        : '${g.date}|$b|$a|${g.scoreB}|${g.scoreA}';
    perKey.putIfAbsent(key, () => {}).putIfAbsent(g.source, () => []).add(g);
  }
  final out = <Game>[];
  for (final bySource in perKey.values) {
    // Same-source copies of one game in one event (e.g. the same team listed
    // twice) collapse by event; then keep the source with the most games.
    final candidates = bySource.values.map((list) {
      final byEvent = <String, List<Game>>{};
      for (final g in list) {
        byEvent.putIfAbsent(g.eventId, () => []).add(g);
      }
      return byEvent.values.reduce((x, y) => x.length >= y.length ? x : y);
    }).toList();
    out.addAll(candidates.reduce((x, y) => x.length >= y.length ? x : y));
  }
  return out;
}

/// The review report; also adds each possible duplicate to [suggestions].
String _review(GroupResult grouping, Map<String, SourceTeam> teams,
    Map<String, Set<String>> eventsOf, List<({List<String> keys, String reason})> suggestions) {
  String describe(String k) {
    final t = teams[k];
    return '`$k` ${t?.name ?? '?'} (${t?.city ?? ''}, ${t?.state ?? ''}; '
        '${eventsOf[k]?.length ?? 0} events)';
  }

  final b = StringBuffer()
    ..writeln('# Team matching review')
    ..writeln()
    ..writeln('Generated by the pipeline. Fix mistakes in `data/aliases.json`.')
    ..writeln()
    ..writeln('## Merged automatically (${grouping.merged.length})')
    ..writeln()
    ..writeln('Same name and hometown, never in the same event. Undo one with a `split` entry.')
    ..writeln();
  for (final g in grouping.merged) {
    b.writeln('- ${g.map(describe).join(' = ')}');
  }
  b
    ..writeln()
    ..writeln('## Not merged: same name and hometown (${grouping.ambiguous.length})')
    ..writeln()
    ..writeln('They played in the same event or their names give different ages, so they are '
        'probably different squads. Add a `names` entry to tell them apart, or a `merge` entry '
        'if they are one team.')
    ..writeln();
  for (final g in grouping.ambiguous) {
    b.writeln('- ${g.map(describe).join(' / ')}');
    suggestions.add((keys: g, reason: 'Same name and hometown'));
  }

  // Same name, different hometown: often one team listed with two towns.
  final byName = <String, List<String>>{};
  for (final t in teams.values) {
    final n = normalizeTeamName(t.name);
    if (n.isNotEmpty) byName.putIfAbsent(n, () => []).add(t.key);
  }
  final near = byName.values
      .where((ks) => ks.map((k) => grouping.groupOf[k]).toSet().length > 1)
      .where((ks) => ks.map((k) => teams[k]!.city.toLowerCase().trim()).toSet().length > 1)
      .toList();
  b
    ..writeln()
    ..writeln('## Possible duplicates: same name, different hometown (${near.length})')
    ..writeln()
    ..writeln('Add a `merge` entry if these are the same team.')
    ..writeln();
  for (final ks in near) {
    b.writeln('- ${(ks..sort()).map(describe).join(' / ')}');
    suggestions.add((keys: ks, reason: 'Same name, different hometown'));
  }

  // Same hometown, and one name contains all the words of the other, like
  // "LA Bulls - Howell" and "LA Bulls Black 12U - Howell".
  final byCity = <String, List<SourceTeam>>{};
  for (final t in teams.values) {
    if (t.city.isNotEmpty) {
      byCity.putIfAbsent('${t.city.toLowerCase().trim()}|${t.state}', () => []).add(t);
    }
  }
  final similar = <String>[];
  for (final list in byCity.values) {
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        final x = list[i], y = list[j];
        if (grouping.groupOf[x.key] == grouping.groupOf[y.key]) continue;
        final wx = normalizeTeamName(x.name).split(' ').toSet()..remove('');
        final wy = normalizeTeamName(y.name).split(' ').toSet()..remove('');
        if (wx.isEmpty || wy.isEmpty || wx.length == wy.length && wx.containsAll(wy)) continue;
        if (wx.containsAll(wy) || wy.containsAll(wx)) {
          similar.add('- ${[x.key, y.key].map(describe).join(' / ')}');
          suggestions.add((keys: [x.key, y.key]..sort(), reason: 'Similar name, same hometown'));
        }
      }
    }
  }
  b
    ..writeln()
    ..writeln('## Possible duplicates: similar name, same hometown (${similar.length})')
    ..writeln()
    ..writeln('Add a `merge` entry if these are the same team.')
    ..writeln();
  for (final line in similar..sort()) {
    b.writeln(line);
  }
  return b.toString();
}

/// Fixes hometowns typed as `SHREVEPORT` or `Baton ROuge`.
String _titleCase(String s) => s
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

double _round(double v) => (v * 10000).round() / 10000;

class _Stats {
  int wins = 0, losses = 0, ties = 0, runsFor = 0, runsAgainst = 0;
  double _oppSum = 0;
  int get games => wins + losses + ties;
  double get sos => games == 0 ? 0 : _oppSum / games;

  void add(int us, int them, double oppRating) {
    if (us > them) {
      wins++;
    } else if (us < them) {
      losses++;
    } else {
      ties++;
    }
    runsFor += us;
    runsAgainst += them;
    _oppSum += oppRating;
  }
}
