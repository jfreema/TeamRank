import 'package:teamrank_pipeline/teamrank_pipeline.dart';
import 'package:test/test.dart';

void main() {
  test('everyone starts at 0.5', () {
    expect(colleyRatings(3, []), everyElement(closeTo(0.5, 1e-9)));
  });

  test('ratings average 0.5 and winners rate higher', () {
    final r = colleyRatings(2, [Result(0, 1, 5, 2)]);
    expect(r[0], greaterThan(r[1]));
    expect((r[0] + r[1]) / 2, closeTo(0.5, 1e-9));
  });

  test('A beats B, C beats A: C ranks above A, A above B', () {
    const a = 0, b = 1, c = 2;
    final r = colleyRatings(3, [Result(a, b, 6, 3), Result(c, a, 4, 2)]);
    expect(r[c], greaterThan(r[a]));
    expect(r[a], greaterThan(r[b]));
  });

  test('beating a winless team counts less than beating a good team', () {
    // X beats a team that never wins; Y beats a team that has beaten others.
    const x = 0, y = 1, winless = 2, good = 3, f1 = 4, f2 = 5, f3 = 6;
    final r = colleyRatings(7, [
      Result(x, winless, 5, 1),
      Result(f1, winless, 5, 1),
      Result(f2, winless, 5, 1),
      Result(y, good, 5, 1),
      Result(good, f1, 5, 1),
      Result(good, f3, 5, 1),
    ]);
    expect(r[y], greaterThan(r[x]));
  });

  test('a bigger win counts more, up to the cap', () {
    final close = colleyRatings(2, [Result(0, 1, 3, 2)]);
    final big = colleyRatings(2, [Result(0, 1, 9, 2)]);
    final capped = colleyRatings(2, [Result(0, 1, 12, 2)]);
    final blowout = colleyRatings(2, [Result(0, 1, 20, 0)]);
    expect(big[0], greaterThan(close[0]));
    expect(capped[0], greaterThan(big[0]));
    expect(blowout[0], closeTo(capped[0], 1e-12), reason: 'no credit past 10 runs');
  });

  test('a one-run win still counts as most of a win', () {
    expect(winShare(3, 2), closeTo(0.64, 1e-9));
    expect(winShare(2, 3), closeTo(0.36, 1e-9));
    expect(winShare(15, 0), 1);
    expect(winShare(4, 4), 0.5);
  });

  test('a tie leaves both teams level', () {
    final r = colleyRatings(2, [Result(0, 1, 4, 4)]);
    expect(r[0], closeTo(r[1], 1e-12));
  });

  test('a weighted win counts more', () {
    final normal = colleyRatings(2, [Result(0, 1, 3, 2)]);
    final heavy = colleyRatings(2, [Result(0, 1, 3, 2, weight: 1.5)]);
    expect(heavy[0], greaterThan(normal[0]));
  });

  test('a head-to-head winner passes a close team it beat', () {
    // Team 0 rates higher overall, but team 1 beat it directly.
    final adj = headToHeadAdjusted([0.58, 0.52, 0.4], [Result(1, 0, 3, 2), Result(0, 2, 5, 1)]);
    expect(adj[1], greaterThan(adj[0]));
    expect(adj[2], 0.4, reason: 'expected results change nothing');
  });

  test('head-to-head only closes part of a big gap', () {
    final adj = headToHeadAdjusted([0.9, 0.3], [Result(1, 0, 3, 2)]);
    expect(adj[0], closeTo(0.84, 1e-9));
    expect(adj[1], closeTo(0.36, 1e-9));
  });

  test('a split series gives no head-to-head edge', () {
    final adj = headToHeadAdjusted([0.6, 0.5], [Result(1, 0, 3, 2), Result(0, 1, 3, 2)]);
    expect(adj, [0.6, 0.5]);
  });

  test('a softened loss costs the loser less and leaves the winner alone', () {
    final full = colleyRatings(2, [Result(0, 1, 3, 2)]);
    final soft = colleyRatings(2, [Result(0, 1, 3, 2, lossScale: 0.4)]);
    expect(soft[1], greaterThan(full[1]));
    expect(soft[1], lessThan(0.5), reason: 'a loss is still a loss');
  });

  test('opponents of opponents count', () {
    // X and Y are both 1-0, each beating a 1-1 team. X's victim beat a team
    // that won its other games; Y's victim beat a team that lost them, so X
    // rates higher even though X and Y never shared an opponent.
    const x = 0, y = 1, vx = 2, vy = 3, strong = 4, weak = 5, s1 = 6, s2 = 7, w1 = 8;
    final r = colleyRatings(9, [
      Result(x, vx, 5, 4),
      Result(y, vy, 5, 4),
      Result(vx, strong, 5, 4),
      Result(vy, weak, 5, 4),
      Result(strong, s1, 5, 4),
      Result(strong, s2, 5, 4),
      Result(w1, weak, 5, 4),
      Result(s1, w1, 5, 4),
      Result(s2, w1, 5, 4),
    ]);
    expect(r[x], greaterThan(r[y]));
  });

  test('blending with the record lifts a winning team on a weak schedule', () {
    // Team 0 went 3-0 against a weak team; team 1 went 1-2 against strong ones.
    final ratings = [0.5, 0.55, 0.3, 0.7];
    final results = [
      Result(0, 2, 5, 1), Result(0, 2, 5, 1), Result(0, 2, 5, 1),
      Result(1, 3, 5, 1), Result(3, 1, 5, 1), Result(3, 1, 5, 1),
    ];
    final blended = blendWithRecord(ratings, results, weights: (inClass: 0, overall: 0.35));
    expect(blended[0], greaterThan(blended[1]));
    expect(blendWithRecord([0.5], [], weights: (inClass: 0, overall: 0.35)), [closeTo(0.5, 1e-12)]);
  });

  test('part of the record is the record against the same class', () {
    // Teams 0 and 3 are both 1-1, but team 0 beat the AA team and team 3
    // lost to it. Team 2 (AAA) never played a AAA team.
    final classOf = ['AA', 'AA', 'AAA', 'AA', 'AAA'];
    final ratings = [0.5, 0.5, 0.5, 0.5, 0.5];
    final results = [
      Result(0, 1, 5, 1), Result(2, 0, 5, 1),
      Result(1, 3, 5, 1), Result(3, 4, 5, 1),
    ];
    final split = blendWithRecord(ratings, results, weights: (inClass: 0.15, overall: 0.10), classOf: classOf);
    final overallOnly = blendWithRecord(ratings, results, weights: (inClass: 0, overall: 0.25), classOf: classOf);
    expect(split[0], greaterThan(split[3]), reason: 'same overall record, better against its class');
    expect(overallOnly[0], closeTo(overallOnly[3], 1e-12));
    expect(split[2], closeTo(overallOnly[2], 1e-12), reason: 'no games in its class: overall record stands in');
  });

  test('a close loss to a strong team earns more than one to a weak team', () {
    final ratings = [0.5, 0.9, 0.3];
    final out = closeGameBonuses(ratings, [Result(0, 1, 9, 10), Result(0, 2, 9, 10), Result(0, 1, 2, 12)],
        maxBonus: 0.3);
    expect(out[0].shareBonus, closeTo(0.13, 1e-9), reason: 'half the 0.4 gap, kept short of a tie');
    expect(out[1].shareBonus, closeTo(-0.1, 1e-9), reason: 'losing a close one to a weaker team');
    expect(out[2].shareBonus, 0, reason: 'blowouts get no bonus');
    expect(winShare(9, 10) + out[0].shareBonus, lessThan(0.5), reason: 'still a loss');
  });
}
