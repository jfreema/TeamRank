import 'package:teamrank_pipeline/teamrank_pipeline.dart';
import 'package:test/test.dart';

Game game(String source, String event, String a, String b, int sa, int sb,
        {String date = '2026-10-10'}) =>
    Game(
      source: source,
      eventId: event,
      eventName: 'Event $event',
      date: date,
      division: '12U-AA',
      teamA: a,
      teamB: b,
      scoreA: sa,
      scoreB: sb,
    );

SourceTeam team(String key, String name, String city,
        {String state = 'LA'}) =>
    SourceTeam(key: key, name: name, city: city, state: state);

void main() {
  group('normalizeTeamName', () {
    test('ignores age labels, punctuation and filler words', () {
      expect(normalizeTeamName('Louisiana Stars - Nations 12U'),
          normalizeTeamName('LOUISIANA STARS NATIONS'));
      expect(normalizeTeamName('Ripzz Baseball Academy'),
          normalizeTeamName('Ripzz Academy'));
    });

    test('keeps squad names apart', () {
      expect(normalizeTeamName('Hammond Yankees - Hills'),
          isNot(normalizeTeamName('Hammond Yankees')));
    });
  });

  group('groupTeams', () {
    test('merges the same team listed by two orgs', () {
      final g = groupTeams([
        team('otc:1', 'Slidell Raptors', 'Slidell'),
        team('2d:aa', 'Slidell Raptors 12U', 'Slidell'),
      ], Aliases());
      expect(g.groupOf['otc:1'], g.groupOf['2d:aa']);
    });

    test('merges a team registered twice with one org', () {
      final g = groupTeams([
        team('2d:aa', 'Bobcats', 'Denham Springs'),
        team('2d:bb', 'Bobcats', 'Denham Springs'),
      ], Aliases(), eventsOf: {
        '2d:aa': {'2d:1'},
        '2d:bb': {'2d:2'},
      });
      expect(g.groupOf['2d:aa'], g.groupOf['2d:bb']);
    });

    test('keeps same-name teams apart when they played the same event', () {
      final g = groupTeams([
        team('2d:aa', 'Bobcats', 'Denham Springs'),
        team('2d:bb', 'Bobcats', 'Denham Springs'),
      ], Aliases(), eventsOf: {
        '2d:aa': {'2d:1'},
        '2d:bb': {'2d:1'},
      });
      expect(g.groupOf['2d:aa'], isNot(g.groupOf['2d:bb']));
      expect(g.ambiguous, hasLength(1));
    });

    test('does not merge squads whose names give different ages', () {
      final g = groupTeams([
        team('2d:aa', 'Strikeforce 12U', 'DeRidder'),
        team('2d:bb', 'Strikeforce 11U', 'Deridder'),
      ], Aliases());
      expect(g.groupOf['2d:aa'], isNot(g.groupOf['2d:bb']));
    });

    test('allows a one-year class gap across orgs, not within one', () {
      SourceTeam t(String k, String cls) =>
          SourceTeam(key: k, name: 'Raptors', city: 'Slidell', state: 'LA', ageClass: cls);
      final across = groupTeams([t('otc:1', '12U-AA'), t('gs:1', '13 & Under A')], Aliases());
      expect(across.groupOf['otc:1'], across.groupOf['gs:1']);
      final within = groupTeams([t('otc:1', '12U-AA'), t('otc:2', '13U-AA')], Aliases());
      expect(within.groupOf['otc:1'], isNot(within.groupOf['otc:2']));
      final far = groupTeams([t('otc:1', '11U-AA'), t('gs:1', '13 & Under A')], Aliases());
      expect(far.groupOf['otc:1'], isNot(far.groupOf['gs:1']));
    });

    test('does not merge different hometowns without an alias', () {
      final teams = [
        team('otc:1', 'Tigers', 'Gonzales'),
        team('2d:aa', 'Tigers', 'Walker'),
      ];
      expect(groupTeams(teams, Aliases()).groupOf['otc:1'], 'otc:1');
      final merged = groupTeams(teams, Aliases(merge: [
        ['otc:1', '2d:aa']
      ]));
      expect(merged.groupOf['otc:1'], merged.groupOf['2d:aa']);
    });

    test('split blocks an automatic merge', () {
      final g = groupTeams([
        team('otc:1', 'Slidell Raptors', 'Slidell'),
        team('2d:aa', 'Slidell Raptors', 'Slidell'),
      ], Aliases(split: [
        ['otc:1', '2d:aa']
      ]));
      expect(g.groupOf['otc:1'], isNot(g.groupOf['2d:aa']));
    });
  });

  test('levelOf groups AA with A, and AAA with Majors', () {
    expect(levelOf('12 & Under Class B'), 'AA');
    expect(levelOf('13 & Under AAA'), 'AAA');
    expect(levelOf('12U-AA'), 'AA');
    expect(levelOf('12u A'), 'AA');
    expect(levelOf('12u AAA'), 'AAA');
    expect(levelOf('12U-AAA'), 'AAA');
    expect(levelOf('11u Major'), 'AAA');
    expect(levelOf('12u Open'), isNull);
    expect(levelOf('12u'), isNull);
  });

  group('dedupeGames', () {
    final ids = {
      'otc:1': 'otc:1',
      'otc:2': 'otc:2',
      '2d:a': 'otc:1',
      '2d:b': 'otc:2',
    };

    test('keeps one copy of a game reported by two sources', () {
      final out = dedupeGames([
        game('otc', '9', 'otc:1', 'otc:2', 5, 3),
        game('2d', '77', '2d:b', '2d:a', 3, 5),
      ], ids);
      expect(out, hasLength(1));
    });

    test('keeps a real rematch with the same score', () {
      final out = dedupeGames([
        game('otc', '9', 'otc:1', 'otc:2', 5, 3),
        game('otc', '9', 'otc:1', 'otc:2', 5, 3),
      ], ids);
      expect(out, hasLength(2));
    });

    test('keeps different results between the same teams', () {
      final out = dedupeGames([
        game('otc', '9', 'otc:1', 'otc:2', 5, 3),
        game('otc', '9', 'otc:2', 'otc:1', 6, 1),
      ], ids);
      expect(out, hasLength(2));
    });

    test('games on different days are different games', () {
      final out = dedupeGames([
        game('otc', '9', 'otc:1', 'otc:2', 5, 3, date: '2026-10-10'),
        game('2d', '7', '2d:a', '2d:b', 5, 3, date: '2026-10-17'),
      ], ids);
      expect(out, hasLength(2));
    });
  });

  test('buildRankings ranks only Louisiana teams and counts each game once', () {
    final otc = SourceCache(source: 'otc', season: '2026-27', teams: {
      'otc:1': team('otc:1', 'Raptors', 'Slidell'),
      'otc:2': team('otc:2', 'Vice', 'Biloxi', state: 'MS'),
      'otc:3': team('otc:3', 'Stars', 'Hammond'),
    }, events: {
      '9': EventRecord(
        id: '9',
        name: 'Fall Bash',
        startDate: '2026-10-10',
        endDate: '2026-10-11',
        isFinal: true,
        teamKeys: ['otc:1', 'otc:2', 'otc:3'],
        games: [
          game('otc', '9', 'otc:1', 'otc:2', 5, 3),
          game('otc', '9', 'otc:2', 'otc:3', 4, 1),
        ],
      ),
    });
    final twoD = SourceCache(source: '2d', season: '2026-27', teams: {
      '2d:a': team('2d:a', 'Raptors 12u', 'Slidell'),
      '2d:b': team('2d:b', 'Vice', 'Biloxi', state: 'MS'),
    }, events: {
      '77': EventRecord(
        id: '77',
        name: 'Co-sanctioned Bash',
        startDate: '2026-10-10',
        endDate: '2026-10-11',
        isFinal: true,
        teamKeys: ['2d:a', '2d:b'],
        games: [game('2d', '77', '2d:a', '2d:b', 5, 3)],
      ),
    });
    final (:rankings, :review) = buildRankings(
      caches: [otc, twoD],
      aliases: Aliases(),
      season: '2026-27',
      generatedAt: DateTime.utc(2026, 10, 20),
    );
    final teams = (rankings['teams'] as List).cast<Map<String, dynamic>>();
    final raptors = teams.firstWhere((t) => t['name'] == 'Raptors');
    expect(raptors['rank'], 1);
    expect(raptors['wins'], 1, reason: 'the game both orgs reported counts once');
    expect(teams.firstWhere((t) => t['name'] == 'Vice')['rank'], isNull);
    expect(teams.firstWhere((t) => t['name'] == 'Stars')['rank'], 2);
    expect(rankings['games'], hasLength(2));
    expect(raptors['level'], isNull, reason: 'no class given');
    expect(review, contains('Merged automatically (2)'));
  });

  test('AA and AAA teams get separate ranks from one shared rating pool', () {
    SourceTeam t(String k, String name, String cls) =>
        SourceTeam(key: k, name: name, city: name, state: 'LA', ageClass: cls);
    final cache = SourceCache(source: 'otc', season: '2026-27', teams: {
      'otc:1': t('otc:1', 'Big', '12U-AAA'),
      'otc:2': t('otc:2', 'Mid', '12U-AA'),
      'otc:3': t('otc:3', 'Low', '12U-AA'),
      'otc:4': t('otc:4', 'Low2', '12U-AAA'),
    }, events: {
      '1': EventRecord(
        id: '1', name: 'E', startDate: '2026-10-10', endDate: '2026-10-11',
        isFinal: true, teamKeys: [],
        games: [
          game('otc', '1', 'otc:2', 'otc:1', 6, 2), // AA team beats AAA team
          game('otc', '1', 'otc:1', 'otc:4', 6, 2),
          game('otc', '1', 'otc:2', 'otc:3', 6, 2),
        ],
      ),
    });
    final (:rankings, review: _) = buildRankings(
      caches: [cache],
      aliases: Aliases(levels: {'otc:3': 'AAA'}),
      season: '2026-27',
      generatedAt: DateTime.utc(2026, 10, 20),
    );
    final byName = {
      for (final x in (rankings['teams'] as List).cast<Map<String, dynamic>>()) x['name']: x
    };
    expect(byName['Mid']!['rank'], 1);
    expect(byName['Mid']!['level'], 'AA');
    expect(byName['Mid']!['levelRank'], 1);
    expect(byName['Big']!['level'], 'AAA');
    expect(byName['Big']!['levelRank'], 1, reason: 'AAA list ranks separately');
    expect(byName['Low']!['level'], 'AAA', reason: 'aliases can override the level');
    expect(rankings['ages'], {
      '12': {'teams': 4, 'AA': 1, 'AAA': 3}
    });
  });

  test('teams stay at their registered age and only 11U-14U are ranked', () {
    SourceTeam t(String k, String cls) =>
        SourceTeam(key: k, name: k, city: k, state: 'LA', ageClass: cls);
    final cache = SourceCache(source: 'otc', season: '2026-27', teams: {
      'otc:up': t('otc:up', '11U-AA'),
      'otc:a': t('otc:a', '12U-AA'),
      'otc:b': t('otc:b', '12U-AA'),
      'otc:old': t('otc:old', '15U-AA'),
    }, events: {
      '1': EventRecord(
        id: '1', name: 'E', startDate: '2026-10-10', endDate: '2026-10-11',
        isFinal: true, teamKeys: [],
        games: [
          // An 11U team playing up in a 12U division.
          game('otc', '1', 'otc:up', 'otc:a', 6, 2),
          game('otc', '1', 'otc:a', 'otc:b', 6, 2),
          game('otc', '1', 'otc:old', 'otc:b', 6, 2),
        ],
      ),
    });
    final (:rankings, review: _) = buildRankings(
      caches: [cache],
      aliases: Aliases(),
      season: '2026-27',
      generatedAt: DateTime.utc(2026, 10, 20),
    );
    final byName = {
      for (final x in (rankings['teams'] as List).cast<Map<String, dynamic>>()) x['name']: x
    };
    expect(byName['otc:up']!['age'], 11);
    expect(byName['otc:up']!['rank'], 1, reason: 'ranked within 11U');
    expect(byName['otc:a']!['age'], 12);
    expect(byName['otc:a']!['rank'], 1);
    expect(byName['otc:old']!['rank'], isNull, reason: '15U is outside the covered ages');
    expect(byName['otc:old']!['age'], 15, reason: 'still listed as an opponent');
    expect(rankings['ages'], {
      '11': {'teams': 1, 'AA': 1, 'AAA': 0},
      '12': {'teams': 2, 'AA': 2, 'AAA': 0},
    });
  });

  test('beating a AAA team counts more than beating an AA team with the same record', () {
    SourceTeam t(String k, String cls) =>
        SourceTeam(key: k, name: k, city: k, state: 'LA', ageClass: cls);
    final cache = SourceCache(source: 'otc', season: '2026-27', teams: {
      'otc:x': t('otc:x', '12U-AA'),
      'otc:y': t('otc:y', '12U-AA'),
      'otc:aaa': t('otc:aaa', '12U-AAA'),
      'otc:aa': t('otc:aa', '12U-AA'),
    }, events: {
      '1': EventRecord(
        id: '1', name: 'E', startDate: '2026-10-10', endDate: '2026-10-11',
        isFinal: true, teamKeys: [],
        games: [
          game('otc', '1', 'otc:x', 'otc:aaa', 5, 2),
          game('otc', '1', 'otc:y', 'otc:aa', 5, 2),
        ],
      ),
    });
    final (:rankings, review: _) = buildRankings(
      caches: [cache],
      aliases: Aliases(),
      season: '2026-27',
      generatedAt: DateTime.utc(2026, 10, 20),
    );
    final r = {
      for (final x in (rankings['teams'] as List).cast<Map<String, dynamic>>()) x['id']: x['rating'] as double
    };
    expect(r['otc:x']!, greaterThan(r['otc:y']!));
  });

  test('beating a Majors team counts more than beating a AAA team', () {
    SourceTeam t(String k, String cls) =>
        SourceTeam(key: k, name: k, city: k, state: 'LA', ageClass: cls);
    final cache = SourceCache(source: 'otc', season: '2026-27', teams: {
      'otc:x': t('otc:x', '12U-AA'),
      'otc:y': t('otc:y', '12U-AA'),
      'otc:maj': t('otc:maj', '12u Major'),
      'otc:aaa': t('otc:aaa', '12U-AAA'),
    }, events: {
      '1': EventRecord(
        id: '1', name: 'E', startDate: '2026-10-10', endDate: '2026-10-11',
        isFinal: true, teamKeys: [],
        games: [
          game('otc', '1', 'otc:x', 'otc:maj', 5, 2),
          game('otc', '1', 'otc:y', 'otc:aaa', 5, 2),
        ],
      ),
    });
    final (:rankings, review: _) = buildRankings(
      caches: [cache],
      aliases: Aliases(),
      season: '2026-27',
      generatedAt: DateTime.utc(2026, 10, 20),
    );
    final r = {
      for (final x in (rankings['teams'] as List).cast<Map<String, dynamic>>()) x['id']: x['rating'] as double
    };
    expect(r['otc:x']!, greaterThan(r['otc:y']!));
  });

  test('losing to a higher class costs less', () {
    SourceTeam t(String k, String cls) =>
        SourceTeam(key: k, name: k, city: k, state: 'LA', ageClass: cls);
    final cache = SourceCache(source: 'otc', season: '2026-27', teams: {
      'otc:x': t('otc:x', '12U-AA'),
      'otc:y': t('otc:y', '12U-AA'),
      'otc:z': t('otc:z', '12U-AA'),
      'otc:maj': t('otc:maj', '12u Major'),
      'otc:aaa': t('otc:aaa', '12U-AAA'),
      'otc:aa': t('otc:aa', '12U-AA'),
    }, events: {
      '1': EventRecord(
        id: '1', name: 'E', startDate: '2026-10-10', endDate: '2026-10-11',
        isFinal: true, teamKeys: [],
        games: [
          game('otc', '1', 'otc:maj', 'otc:x', 5, 2),
          game('otc', '1', 'otc:aaa', 'otc:y', 5, 2),
          game('otc', '1', 'otc:aa', 'otc:z', 5, 2),
        ],
      ),
    });
    final (:rankings, review: _) = buildRankings(
      caches: [cache],
      aliases: Aliases(),
      season: '2026-27',
      generatedAt: DateTime.utc(2026, 10, 20),
    );
    final r = {
      for (final x in (rankings['teams'] as List).cast<Map<String, dynamic>>()) x['id']: x['rating'] as double
    };
    expect(r['otc:x']!, greaterThan(r['otc:y']!), reason: 'loss to Majors costs least');
    expect(r['otc:y']!, greaterThan(r['otc:z']!), reason: 'loss to AAA costs less than to AA');
  });

  test('logos come from 2D first, then OTC, then Grand Slam', () {
    SourceTeam t(String k, String? logo) => SourceTeam(key: k, name: 'X', logo: logo);
    expect(logoFor([t('gs:1', 'g'), t('otc:1', 'o'), t('2d:1', 'd')]), 'd');
    expect(logoFor([t('gs:1', 'g'), t('otc:1', 'o'), t('2d:1', '')]), 'o');
    expect(logoFor([t('gs:1', 'g'), t('otc:1', null)]), 'g');
    expect(logoFor([t('otc:1', '')]), isNull);
  });
}
