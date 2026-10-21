/// The rankings file written by the pipeline (`web/data/rankings.json`).
class RankingsData {
  RankingsData({
    required this.generatedAt,
    required this.season,
    required this.state,
    required this.teams,
    required this.games,
    required this.sources,
    this.suggestions = const [],
  });

  final DateTime generatedAt;
  final String season;
  final String state;
  final List<Team> teams;
  final List<GameResult> games;
  final Map<String, ({int events, int games})> sources;

  /// Listings that may be the same team, for the admin console.
  final List<Suggestion> suggestions;

  late final Map<String, Team> teamsById = {for (final t in teams) t.id: t};

  /// Louisiana teams, best rating first.
  late final List<Team> ranked =
      teams.where((t) => t.rank != null).toList()
        ..sort((a, b) => b.rating.compareTo(a.rating));

  /// The age groups that have ranked teams, youngest first.
  late final List<int> ages =
      ranked.map((t) => t.age).whereType<int>().toSet().toList()..sort();

  List<GameResult> gamesFor(String teamId) =>
      games.where((g) => g.a == teamId || g.b == teamId).toList()
        ..sort((x, y) => y.date.compareTo(x.date));

  factory RankingsData.fromJson(Map<String, dynamic> j) => RankingsData(
        generatedAt: DateTime.parse(j['generatedAt'] as String).toLocal(),
        season: j['season'] as String? ?? '',
        state: j['state'] as String? ?? 'LA',
        teams: (j['teams'] as List)
            .map((t) => Team.fromJson(t as Map<String, dynamic>))
            .toList(),
        games: (j['games'] as List)
            .map((g) => GameResult.fromJson(g as Map<String, dynamic>))
            .toList(),
        sources: (j['sources'] as Map<String, dynamic>? ?? {}).map((k, v) {
          final m = v as Map<String, dynamic>;
          return MapEntry(k, (events: m['events'] as int, games: m['games'] as int));
        }),
        suggestions: (j['suggestions'] as List? ?? [])
            .map((x) => Suggestion.fromJson(x as Map<String, dynamic>))
            .toList(),
      );
}

class Team {
  Team({
    required this.id,
    required this.name,
    required this.city,
    required this.state,
    required this.age,
    required this.rank,
    required this.level,
    required this.levelRank,
    required this.rating,
    this.levelRating,
    required this.sos,
    required this.wins,
    required this.losses,
    required this.ties,
    required this.runsFor,
    required this.runsAgainst,
    required this.sources,
    this.logo,
  });

  final String id;
  final String name;
  final String city;
  final String state;
  /// The age group the team registered in, such as 12 for 12U.
  final int? age;

  /// Rank among Louisiana teams of the same [age]; null for teams that are
  /// not ranked (out of state, or outside the covered ages).
  final int? rank;

  /// `AA` (AA and A teams), `AAA` (AAA and Majors), or null if unknown.
  final String? level;

  /// Rank within [age] and [level].
  final int? levelRank;
  final double rating;

  /// The rating behind [levelRank]. Class lists blend in some of the team's
  /// own record, so it differs from [rating].
  final double? levelRating;
  final double sos;
  final int wins;
  final int losses;
  final int ties;
  final int runsFor;
  final int runsAgainst;
  final List<TeamSource> sources;
  final String? logo;

  int get games => wins + losses + ties;
  String get record => ties > 0 ? '$wins-$losses-$ties' : '$wins-$losses';
  String get hometown =>
      [city, state].where((s) => s.isNotEmpty).join(', ');
  int get runDiff => runsFor - runsAgainst;

  factory Team.fromJson(Map<String, dynamic> j) => Team(
        id: j['id'] as String,
        name: j['name'] as String,
        city: j['city'] as String? ?? '',
        state: j['state'] as String? ?? '',
        age: j['age'] as int?,
        rank: j['rank'] as int?,
        level: j['level'] as String?,
        levelRank: j['levelRank'] as int?,
        rating: (j['rating'] as num).toDouble(),
        levelRating: (j['levelRating'] as num?)?.toDouble(),
        sos: (j['sos'] as num? ?? 0).toDouble(),
        wins: j['wins'] as int? ?? 0,
        losses: j['losses'] as int? ?? 0,
        ties: j['ties'] as int? ?? 0,
        runsFor: j['runsFor'] as int? ?? 0,
        runsAgainst: j['runsAgainst'] as int? ?? 0,
        sources: (j['sources'] as List? ?? [])
            .map((s) => TeamSource.fromJson(s as Map<String, dynamic>))
            .toList(),
        logo: j['logo'] as String?,
      );
}

class TeamSource {
  TeamSource({
    required this.key,
    required this.source,
    required this.name,
    required this.url,
    required this.ageClass,
  });

  /// `<source>:<id>`, the id the pipeline and admin links use.
  final String key;
  final String source;
  final String name;
  final String url;
  final String ageClass;

  String get label => sourceLabel(source);

  factory TeamSource.fromJson(Map<String, dynamic> j) => TeamSource(
        key: j['key'] as String? ?? '',
        source: j['source'] as String,
        name: j['name'] as String? ?? '',
        url: j['url'] as String? ?? '',
        ageClass: j['ageClass'] as String? ?? '',
      );
}

class GameResult {
  GameResult({
    required this.date,
    required this.source,
    required this.event,
    required this.division,
    required this.a,
    required this.b,
    required this.sa,
    required this.sb,
  });

  final DateTime date;
  final String source;
  final String event;
  final String division;
  final String a;
  final String b;
  final int sa;
  final int sb;

  /// This game from [teamId]'s side.
  ({String opponent, int us, int them}) from(String teamId) =>
      teamId == a ? (opponent: b, us: sa, them: sb) : (opponent: a, us: sb, them: sa);

  factory GameResult.fromJson(Map<String, dynamic> j) => GameResult(
        date: DateTime.parse(j['date'] as String),
        source: j['source'] as String,
        event: j['event'] as String? ?? '',
        division: j['division'] as String? ?? '',
        a: j['a'] as String,
        b: j['b'] as String,
        sa: j['sa'] as int,
        sb: j['sb'] as int,
      );
}

String ageLabel(int? age) => age == null ? '' : '${age}U';

String levelLabel(String level) => level == 'AAA' ? 'AAA/Majors' : level;

String sourceLabel(String source) => switch (source) {
      'otc' => 'OTC Sports',
      '2d' => '2D Sports',
      'gs' => 'Grand Slam',
      _ => source,
    };

class Suggestion {
  Suggestion({required this.reason, required this.listings});

  final String reason;
  final List<Listing> listings;

  List<String> get keys => [for (final l in listings) l.key];

  factory Suggestion.fromJson(Map<String, dynamic> j) => Suggestion(
        reason: j['reason'] as String? ?? '',
        listings: (j['teams'] as List)
            .map((t) => Listing.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
}

/// One org's listing of a team.
class Listing {
  Listing({
    required this.key,
    required this.name,
    required this.city,
    required this.state,
    required this.ageClass,
    required this.events,
  });

  final String key;
  final String name;
  final String city;
  final String state;
  final String ageClass;
  final int events;

  String get source => key.split(':').first;

  factory Listing.fromJson(Map<String, dynamic> j) => Listing(
        key: j['key'] as String,
        name: j['name'] as String? ?? '',
        city: j['city'] as String? ?? '',
        state: j['state'] as String? ?? '',
        ageClass: j['ageClass'] as String? ?? '',
        events: j['games'] as int? ?? 0,
      );
}
