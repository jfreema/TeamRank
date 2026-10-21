import 'model.dart';

/// Grand Slam runs fast pitch softball on the same site, with the same event
/// and team IDs as baseball. Softball events are often named "Fast Pitch"
/// and softball teams register in classes like `12 & Under Class C` rather
/// than A / AA / AAA.
final _softballName = RegExp(r'fast\s*-?\s*pitch|softball|\bFP\b', caseSensitive: false);
final _softballClass = RegExp(r'\bclass\s+[A-D]\b', caseSensitive: false);

bool isSoftballTeam(SourceTeam t) =>
    _softballClass.hasMatch(t.ageClass) || _softballName.hasMatch(t.ageClass);

/// True for an event named as softball, or one where most of the teams that
/// played are softball teams.
bool isSoftballEvent(EventRecord e, Map<String, SourceTeam> teams) {
  if (_softballName.hasMatch(e.name)) return true;
  final keys = {for (final g in e.games) ...[g.teamA, g.teamB]};
  if (keys.isEmpty) return false;
  final softball = keys.where((k) => teams[k] != null && isSoftballTeam(teams[k]!)).length;
  return softball * 2 > keys.length;
}

/// [cache] without softball events, softball teams, or games involving them.
SourceCache withoutSoftball(SourceCache cache) {
  final dropTeams = {
    for (final t in cache.teams.values)
      if (isSoftballTeam(t)) t.key
  };
  return SourceCache(
    source: cache.source,
    season: cache.season,
    teams: {
      for (final e in cache.teams.entries)
        if (!dropTeams.contains(e.key)) e.key: e.value
    },
    events: {
      for (final e in cache.events.entries)
        if (!isSoftballEvent(e.value, cache.teams))
          e.key: EventRecord(
            id: e.value.id,
            name: e.value.name,
            startDate: e.value.startDate,
            endDate: e.value.endDate,
            isFinal: e.value.isFinal,
            teamKeys: e.value.teamKeys,
            games: [
              for (final g in e.value.games)
                if (!dropTeams.contains(g.teamA) && !dropTeams.contains(g.teamB)) g
            ],
          )
    },
  );
}
