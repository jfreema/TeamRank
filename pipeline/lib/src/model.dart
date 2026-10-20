/// Core data types shared by the scrapers, the ranking engine and the output.
library;

/// A team as one source knows it. [key] is `<source>:<sourceTeamId>`.
class SourceTeam {
  SourceTeam({
    required this.key,
    required this.name,
    this.city = '',
    this.state = '',
    this.ageClass = '',
    this.url = '',
  });

  final String key;
  String name;
  String city;
  String state;
  String ageClass;
  String url;

  String get source => key.split(':').first;

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'city': city,
        'state': state,
        'ageClass': ageClass,
        'url': url,
      };

  factory SourceTeam.fromJson(Map<String, dynamic> j) => SourceTeam(
        key: j['key'] as String,
        name: j['name'] as String? ?? '',
        city: j['city'] as String? ?? '',
        state: j['state'] as String? ?? '',
        ageClass: j['ageClass'] as String? ?? '',
        url: j['url'] as String? ?? '',
      );
}

/// One completed game between two source teams.
class Game {
  Game({
    required this.source,
    required this.eventId,
    required this.eventName,
    required this.date,
    required this.division,
    required this.teamA,
    required this.teamB,
    required this.scoreA,
    required this.scoreB,
  });

  final String source;
  final String eventId;
  final String eventName;

  /// ISO date, `yyyy-mm-dd`.
  final String date;
  final String division;
  final String teamA;
  final String teamB;
  final int scoreA;
  final int scoreB;

  Map<String, dynamic> toJson() => {
        'source': source,
        'eventId': eventId,
        'eventName': eventName,
        'date': date,
        'division': division,
        'teamA': teamA,
        'teamB': teamB,
        'scoreA': scoreA,
        'scoreB': scoreB,
      };

  factory Game.fromJson(Map<String, dynamic> j) => Game(
        source: j['source'] as String,
        eventId: '${j['eventId']}',
        eventName: j['eventName'] as String? ?? '',
        date: j['date'] as String,
        division: j['division'] as String? ?? '',
        teamA: j['teamA'] as String,
        teamB: j['teamB'] as String,
        scoreA: j['scoreA'] as int,
        scoreB: j['scoreB'] as int,
      );
}

/// What a scraper knows about one event: its games and whether it is over.
class EventRecord {
  EventRecord({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.isFinal,
    required this.games,
    required this.teamKeys,
  });

  final String id;
  final String name;
  final String startDate;
  final String endDate;

  /// Final events are never fetched again.
  final bool isFinal;
  final List<Game> games;
  final List<String> teamKeys;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startDate': startDate,
        'endDate': endDate,
        'final': isFinal,
        'teamKeys': teamKeys,
        'games': games.map((g) => g.toJson()).toList(),
      };

  factory EventRecord.fromJson(Map<String, dynamic> j) => EventRecord(
        id: '${j['id']}',
        name: j['name'] as String? ?? '',
        startDate: j['startDate'] as String? ?? '',
        endDate: j['endDate'] as String? ?? '',
        isFinal: j['final'] as bool? ?? false,
        teamKeys: (j['teamKeys'] as List? ?? []).cast<String>(),
        games: (j['games'] as List? ?? [])
            .map((g) => Game.fromJson(g as Map<String, dynamic>))
            .toList(),
      );
}

/// Everything one source has scraped this season. Saved to `data/<source>.json`
/// so later runs only fetch events that are new or still in progress.
class SourceCache {
  SourceCache({
    required this.source,
    required this.season,
    Map<String, SourceTeam>? teams,
    Map<String, EventRecord>? events,
  })  : teams = teams ?? {},
        events = events ?? {};

  final String source;
  final String season;
  final Map<String, SourceTeam> teams;
  final Map<String, EventRecord> events;

  Iterable<Game> get games => events.values.expand((e) => e.games);

  Map<String, dynamic> toJson() => {
        'source': source,
        'season': season,
        'teams': {
          for (final k in (teams.keys.toList()..sort())) k: teams[k]!.toJson()
        },
        'events': {
          for (final k in (events.keys.toList()..sort())) k: events[k]!.toJson()
        },
      };

  factory SourceCache.fromJson(Map<String, dynamic> j) => SourceCache(
        source: j['source'] as String,
        season: j['season'] as String? ?? '',
        teams: (j['teams'] as Map<String, dynamic>? ?? {}).map((k, v) =>
            MapEntry(k, SourceTeam.fromJson(v as Map<String, dynamic>))),
        events: (j['events'] as Map<String, dynamic>? ?? {}).map((k, v) =>
            MapEntry(k, EventRecord.fromJson(v as Map<String, dynamic>))),
      );
}
