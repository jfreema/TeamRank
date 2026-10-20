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

  test('margin of victory does not matter', () {
    final close = colleyRatings(2, [Result(0, 1, 3, 2)]);
    final blowout = colleyRatings(2, [Result(0, 1, 20, 0)]);
    expect(close[0], closeTo(blowout[0], 1e-12));
  });

  test('a tie leaves both teams level', () {
    final r = colleyRatings(2, [Result(0, 1, 4, 4)]);
    expect(r[0], closeTo(r[1], 1e-12));
  });
}
