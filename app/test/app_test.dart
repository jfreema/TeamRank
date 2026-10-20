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

void main() {
  testWidgets('shows ranked Louisiana teams and a team game log', (tester) async {
    await tester.pumpWidget(TeamRankApp(loader: () async => sample()));
    await tester.pumpAndSettle();

    // Opens on the 12U AA list.
    expect(find.text('Walker Elite'), findsOneWidget);
    expect(find.text('Slidell Raptors'), findsNothing);
    expect(find.text('Houma Heat'), findsNothing);

    await tester.tap(find.text('13U'));
    await tester.pumpAndSettle();
    expect(find.text('Houma Heat'), findsOneWidget);
    expect(find.text('Walker Elite'), findsNothing);
    await tester.tap(find.text('12U'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AAA / Majors'));
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
    expect(find.text('AAA / Majors rank'), findsOneWidget);
    expect(find.text('12U rank'), findsOneWidget);
    expect(find.text('3–2'), findsOneWidget);
    expect(find.text('vs Mississippi Vice (MS)'), findsOneWidget);
  });
}
