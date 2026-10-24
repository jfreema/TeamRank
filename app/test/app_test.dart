import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamrank/main.dart';
import 'package:teamrank/models.dart';

RankingsData sample() => RankingsData.fromJson({
      'generatedAt': '2026-10-20T06:00:00Z',
      'season': '2026-27',
      'state': 'LA',
      'sources': {
        'otc': {'events': 1, 'games': 2},
      },
      'teams': [
        {'id': 'otc:1', 'name': 'Slidell Raptors', 'city': 'Slidell', 'state': 'LA', 'age': 12, 'rank': 1, 'level': 'AAA', 'levelRank': 1,
         'rating': 0.61, 'sos': 0.5, 'wins': 2, 'losses': 0, 'ties': 0, 'runsFor': 15, 'runsAgainst': 5,
         'classRecords': {'AA': [1, 0, 0], 'Other': [1, 0, 0]},
         'sources': [{'source': 'otc', 'name': 'Slidell Raptors', 'ageClass': '12U-AA', 'url': ''}]},
        {'id': 'otc:2', 'name': 'Walker Elite', 'city': 'Walker', 'state': 'LA', 'age': 12, 'rank': 2, 'level': 'AA', 'levelRank': 1,
         'rating': 0.45, 'sos': 0.55, 'wins': 0, 'losses': 1, 'ties': 0, 'runsFor': 3, 'runsAgainst': 12, 'sources': []},
        {'id': 'otc:4', 'name': 'Houma Heat', 'city': 'Houma', 'state': 'LA', 'age': 13, 'rank': 1, 'level': 'AA', 'levelRank': 1,
         'rating': 0.52, 'sos': 0.5, 'wins': 0, 'losses': 0, 'ties': 0, 'runsFor': 0, 'runsAgainst': 0, 'sources': []},
        {'id': 'otc:3', 'name': 'Mississippi Vice', 'city': 'Biloxi', 'state': 'MS', 'rank': null,
         'rating': 0.44, 'sos': 0.6, 'wins': 0, 'losses': 1, 'ties': 0, 'runsFor': 2, 'runsAgainst': 3, 'sources': []},
      ],
      'games': [
        {'date': '2026-10-10', 'source': 'otc', 'event': 'Gulf Coast', 'division': '12U-AA',
         'a': 'otc:1', 'b': 'otc:2', 'sa': 12, 'sb': 3},
        {'date': '2026-10-11', 'source': 'otc', 'event': 'Gulf Coast', 'division': '12U-AA',
         'a': 'otc:3', 'b': 'otc:1', 'sa': 2, 'sb': 3},
      ],
    });

/// 12U teams with different games played and runs allowed.
RankingsData defenses() {
  Map<String, dynamic> team(String id, String level, int rank, int levelRank, int games, int runsAgainst) => {
        'id': id, 'name': id, 'city': 'Houma', 'state': 'LA', 'age': 12, 'rank': rank, 'level': level,
        'levelRank': levelRank, 'rating': 1 - rank / 10, 'sos': 0.5, 'wins': games, 'losses': 0, 'ties': 0,
        'runsFor': 50, 'runsAgainst': runsAgainst, 'sources': [],
      };
  return RankingsData.fromJson({
    'generatedAt': '2026-10-24T06:00:00Z',
    'season': '2026-27',
    'teams': [
      team('Lucky Ones', 'AA', 1, 1, 1, 0),
      team('Bayou Bombers', 'AA', 2, 2, 6, 6),
      team('Cajun Crush', 'AAA', 3, 1, 5, 10),
      team('Gator Bait', 'AA', 4, 3, 8, 16),
    ],
    'games': [],
  });
}

void main() {
  test('the fewest-runs nod needs 5 games, and a tie goes to more games', () {
    Team t(String id, int games, int runsAgainst) => Team.fromJson(
        {'id': id, 'name': id, 'rank': 1, 'rating': 0.5, 'wins': games, 'runsAgainst': runsAgainst});
    expect(fewestRunsAllowed([t('one game', 1, 0), t('six games', 6, 9), t('five games', 5, 10)])?.id, 'six games');
    expect(fewestRunsAllowed([t('five', 5, 5), t('eight', 8, 8)])?.id, 'eight');
    expect(fewestRunsAllowed([t('four', 4, 0)]), isNull);
  });

  testWidgets('each list ends with the team that allowed the fewest runs per game', (tester) async {
    await tester.pumpWidget(TeamRankApp(loader: () async => defenses()));
    await tester.pumpAndSettle();
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Fewest runs allowed'), 300, scrollable: list);
    expect(find.text('6 runs in 6 games'), findsOneWidget, reason: 'Lucky Ones has only 1 game');
    expect(find.text('1.0'), findsOneWidget);
    expect(find.text('The fewest runs allowed per game by a 12U team with 5 or more games.'), findsOneWidget);

    await tester.ensureVisible(find.text('AAA'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AAA'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Fewest runs allowed'), 300, scrollable: list);
    expect(find.text('10 runs in 5 games'), findsOneWidget);
    expect(find.text('The fewest runs allowed per game by a 12U AAA team with 5 or more games.'), findsOneWidget);

    await tester.ensureVisible(find.text('6+ games'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6+ games'));
    await tester.pumpAndSettle();
    expect(find.text('Fewest runs allowed'), findsNothing, reason: 'no AAA team has 6 games');

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Fewest runs allowed'), 300, scrollable: list);
    expect(find.text('The fewest runs allowed per game by a 12U team with 6 or more games.'), findsOneWidget);
    expect(find.text('6 runs in 6 games'), findsOneWidget);

    await tester.ensureVisible(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'gator');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Fewest runs allowed'), findsNothing, reason: 'not shown on search results');
  });

  testWidgets('shows ranked Louisiana teams and a team game log', (tester) async {
    await tester.pumpWidget(TeamRankApp(loader: () async => sample()));
    await tester.pumpAndSettle();

    // Opens on the oldest age (14U when there is one), on the All list.
    expect(find.text('Houma Heat'), findsOneWidget);
    expect(find.text('Walker Elite'), findsNothing);

    await tester.tap(find.text('12U'));
    await tester.pumpAndSettle();
    expect(find.text('Walker Elite'), findsOneWidget, reason: 'a new age opens on All');
    expect(find.text('Slidell Raptors'), findsOneWidget);

    await tester.tap(find.text('AA'));
    await tester.pumpAndSettle();
    expect(find.text('Walker Elite'), findsOneWidget);
    expect(find.text('Slidell Raptors'), findsNothing);

    await tester.tap(find.text('AAA'));
    await tester.pumpAndSettle();
    expect(find.text('Slidell Raptors'), findsOneWidget);
    expect(find.text('Walker Elite'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Slidell Raptors'), findsOneWidget);
    expect(find.text('Walker Elite'), findsOneWidget);
    expect(find.text('Mississippi Vice'), findsNothing, reason: 'out-of-state teams are not ranked');

    await tester.enterText(find.byType(TextField), 'walker');
    await tester.pump();
    expect(find.text('Slidell Raptors'), findsOneWidget, reason: 'waits for a pause in typing');
    expect(find.byTooltip('Clear search'), findsOneWidget, reason: 'the X shows right away');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Slidell Raptors'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Slidell Raptors'), findsOneWidget, reason: 'the X clears at once');
    expect(find.byTooltip('Clear search'), findsNothing);
    await tester.tap(find.text('Slidell Raptors'));
    await tester.pumpAndSettle();
    expect(find.text('Games (2)'), findsOneWidget);
    expect(find.text('12–3'), findsOneWidget);
    expect(find.text('vs #1 AA Walker Elite'), findsOneWidget);
    expect(find.text('12U AAA rank'), findsOneWidget, reason: 'its class and its rank in it');
    expect(find.text('All 12U rank'), findsOneWidget);
    expect(find.text('vs AA'), findsOneWidget, reason: 'its record against each class it played');
    expect(find.text('vs Other'), findsOneWidget);
    expect(find.text('1-0'), findsNWidgets(2));
    expect(find.text('3–2'), findsOneWidget);
    expect(find.text('vs Mississippi Vice (MS)'), findsOneWidget);

    await tester.tap(find.text('vs Mississippi Vice (MS)'));
    await tester.pumpAndSettle();
    expect(find.text('Class'), findsOneWidget, reason: 'a team on no class list still shows its class');
    expect(find.text('None'), findsOneWidget);
  });
}
