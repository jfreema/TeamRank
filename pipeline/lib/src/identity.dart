import 'model.dart';

/// Manual corrections from `data/aliases.json`:
///
/// ```json
/// {
///   "merge":  [["otc:7158", "2d:fc31e3be-..."]],
///   "split":  [["otc:7069", "2d:60f64dd6-..."]],
///   "names":  {"otc:7158": "Slidell Raptors"},
///   "levels": {"otc:7158": "AAA"},
///   "ages":   {"otc:7158": 12},
///   "exclude": ["2d:..."]
/// }
/// ```
///
/// `merge` joins source teams that are the same real team, `split` stops an
/// automatic match, `names` overrides the display name, and `exclude` drops a
/// team and its games. `levels` sets which ranking list (`AA` or `AAA`) a
/// team appears in when its registered class is wrong or missing, and `ages`
/// sets the age group it is listed under.
class Aliases {
  Aliases({
    this.merge = const [],
    this.split = const [],
    this.names = const {},
    this.levels = const {},
    this.ages = const {},
    this.exclude = const {},
  });

  final List<List<String>> merge;
  final List<List<String>> split;
  final Map<String, String> names;
  final Map<String, String> levels;
  final Map<String, int> ages;
  final Set<String> exclude;

  factory Aliases.fromJson(Map<String, dynamic> j) => Aliases(
        merge: (j['merge'] as List? ?? [])
            .map((g) => (g as List).cast<String>())
            .toList(),
        split: (j['split'] as List? ?? [])
            .map((g) => (g as List).cast<String>())
            .toList(),
        names: (j['names'] as Map? ?? {}).cast<String, String>(),
        levels: (j['levels'] as Map? ?? {}).cast<String, String>(),
        ages: (j['ages'] as Map? ?? {}).map((k, v) => MapEntry(k as String, (v as num).toInt())),
        exclude: (j['exclude'] as List? ?? []).cast<String>().toSet(),
      );

  /// Both sets of corrections; [other] wins where they disagree.
  Aliases combine(Aliases other) => Aliases(
        merge: [...merge, ...other.merge],
        split: [...split, ...other.split],
        names: {...names, ...other.names},
        levels: {...levels, ...other.levels},
        ages: {...ages, ...other.ages},
        exclude: {...exclude, ...other.exclude},
      );
}

/// Lowercased name without age labels, punctuation or filler words, used to
/// spot the same team listed by two different tournament orgs.
String normalizeTeamName(String name) {
  var s = name.toLowerCase();
  s = s.replaceAll('&', ' and ');
  s = s.replaceAll(RegExp(r'\b1[0-4]\s*u\b'), ' ');
  s = s.replaceAll(RegExp(r'\b(baseball|bb|club|travel|the|team)\b'), ' ');
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// The age written in a team name, like 11 for "Strikeforce 11U".
int? _ageInName(String name) {
  final m = RegExp(r'\b(1[0-4])\s*u\b', caseSensitive: false).firstMatch(name);
  return m == null ? null : int.parse(m.group(1)!);
}

/// Groups source teams into real teams, so a team listed twice (by two orgs,
/// or registered twice with one org) is only counted once.
///
/// Teams are matched automatically when their normalized names and hometowns
/// agree, their names or registered classes don't give different ages (an
/// 11U and a 12U squad of one club), and they never played in the same event, since one team cannot
/// be in two dugouts at once. If any two candidates did share an event (say two
/// squads from one club with the same name), the whole group is left alone
/// and reported in [GroupResult.ambiguous] for a manual alias.
/// [eventsOf] maps each source team key to the events it played in.
GroupResult groupTeams(Iterable<SourceTeam> teams, Aliases aliases,
    {Map<String, Set<String>> eventsOf = const {}}) {
  final parent = <String, String>{};
  String find(String k) {
    var root = k;
    while (parent[root] != null && parent[root] != root) {
      root = parent[root]!;
    }
    parent[k] = root;
    return root;
  }

  void union(String a, String b) {
    final ra = find(a), rb = find(b);
    if (ra == rb) return;
    // Keep the alphabetically first key as the group id so ids are stable.
    if (ra.compareTo(rb) < 0) {
      parent[rb] = ra;
    } else {
      parent[ra] = rb;
    }
  }

  final all = teams.where((t) => !aliases.exclude.contains(t.key)).toList();
  for (final t in all) {
    parent[t.key] = t.key;
  }

  final blocked = {
    for (final pair in aliases.split)
      for (final a in pair)
        for (final b in pair)
          if (a != b) '$a|$b'
  };

  final bySignature = <String, List<SourceTeam>>{};
  for (final t in all) {
    final name = normalizeTeamName(t.name);
    if (name.isEmpty || t.city.isEmpty) continue;
    final sig = '$name|${t.city.toLowerCase().trim()}|${t.state.toUpperCase()}';
    bySignature.putIfAbsent(sig, () => []).add(t);
  }
  final merged = <List<String>>[];
  final ambiguous = <List<String>>[];
  for (final group in bySignature.values) {
    if (group.length < 2) continue;
    var clash = false;
    for (var i = 0; i < group.length && !clash; i++) {
      for (var j = i + 1; j < group.length && !clash; j++) {
        final a = eventsOf[group[i].key] ?? const {};
        final b = eventsOf[group[j].key] ?? const {};
        final ageA = _ageInName(group[i].name), ageB = _ageInName(group[j].name);
        final classA = ageOf(group[i].ageClass), classB = ageOf(group[j].ageClass);
        clash = a.any(b.contains) ||
            (ageA != null && ageB != null && ageA != ageB) ||
            (classA != null && classB != null && classA != classB) ||
            blocked.contains('${group[i].key}|${group[j].key}');
      }
    }
    final keys = group.map((t) => t.key).toList()..sort();
    if (clash) {
      ambiguous.add(keys);
      continue;
    }
    for (final k in keys.skip(1)) {
      union(keys.first, k);
    }
    merged.add(keys);
  }

  for (final g in aliases.merge) {
    final present = g.where(parent.containsKey).toList();
    for (final k in present.skip(1)) {
      union(present.first, k);
    }
  }

  return GroupResult(
    {for (final k in parent.keys) k: find(k)},
    merged: merged,
    ambiguous: ambiguous,
  );
}

class GroupResult {
  GroupResult(this.groupOf, {this.merged = const [], this.ambiguous = const []});

  /// Source team key -> group id (the group's alphabetically first key).
  final Map<String, String> groupOf;

  /// Groups merged automatically by name and hometown.
  final List<List<String>> merged;

  /// Same name and hometown, but they played in the same event, so they were
  /// not merged.
  final List<List<String>> ambiguous;
}

/// Which ranking list a team belongs in, from its registered class such as
/// `12U-AA`, `12u AAA` or `11u Major`: `AAA` for AAA and Majors, `AA` for AA
/// and A, or null when the org only lists it as Open or gives no class.
String? levelOf(String ageClass) {
  final c = ageClass.toUpperCase();
  if (RegExp(r'\bMAJORS?\b|AAA').hasMatch(c)) return 'AAA';
  if (RegExp(r'(^|[^A])AA?\b').hasMatch(c.replaceAll(RegExp(r'\d+U'), ''))) return 'AA';
  return null;
}

/// The youngest and oldest age groups the site covers.
const minAge = 11, maxAge = 14;

bool inAgeRange(int? age) => age != null && age >= minAge && age <= maxAge;

/// The age group in a division or class label: 12 for `12U-AA`, `12u Open`
/// or `12U`; null when there is none.
int? ageOf(String label) {
  final m = RegExp(r'\b(\d{1,2})\s*u\b', caseSensitive: false).firstMatch(label);
  return m == null ? null : int.parse(m.group(1)!);
}
