import 'dart:math';

/// A head-to-head result between two teams, by index.
class Result {
  Result(this.a, this.b, this.scoreA, this.scoreB, {this.weight = 1});
  final int a;
  final int b;
  final int scoreA;
  final int scoreB;

  /// How much this game counts; 1 is a normal game.
  final double weight;
}

/// Colley Matrix ratings (Wesley Colley, 2002).
///
/// Each team's rating is 0.5 plus half its net wins, adjusted by the ratings
/// of the teams it played. Solving the whole system at once means beating a
/// team that beat good teams is worth a lot, and beating a winless team is
/// worth little. Margin of victory is ignored on purpose, so running up the
/// score on a weak team gains nothing. Ties count as half a win each.
///
/// Solves `C r = b` where `C[i][i] = 2 + games_i`, `C[i][j] = -games(i,j)` and
/// `b[i] = 1 + (wins_i - losses_i) / 2`. `C` is symmetric positive definite,
/// so Cholesky decomposition works. A game with weight `w` counts as `w`
/// games in `C` and `w` wins or losses in `b`.
List<double> colleyRatings(int teamCount, List<Result> results) {
  final n = teamCount;
  final c = List.generate(n, (i) => List<double>.filled(n, 0));
  final b = List<double>.filled(n, 1);
  for (var i = 0; i < n; i++) {
    c[i][i] = 2;
  }
  for (final r in results) {
    final w = r.weight;
    c[r.a][r.a] += w;
    c[r.b][r.b] += w;
    c[r.a][r.b] -= w;
    c[r.b][r.a] -= w;
    final diff = r.scoreA > r.scoreB ? w / 2 : (r.scoreA < r.scoreB ? -w / 2 : 0.0);
    b[r.a] += diff;
    b[r.b] -= diff;
  }
  return _choleskySolve(c, b);
}

List<double> _choleskySolve(List<List<double>> a, List<double> b) {
  final n = b.length;
  final l = List.generate(n, (_) => List<double>.filled(n, 0));
  for (var j = 0; j < n; j++) {
    var sum = a[j][j];
    final lj = l[j];
    for (var k = 0; k < j; k++) {
      sum -= lj[k] * lj[k];
    }
    lj[j] = sqrt(sum);
    for (var i = j + 1; i < n; i++) {
      final li = l[i];
      var s = a[i][j];
      for (var k = 0; k < j; k++) {
        s -= li[k] * lj[k];
      }
      li[j] = s / lj[j];
    }
  }
  final y = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    var s = b[i];
    for (var k = 0; k < i; k++) {
      s -= l[i][k] * y[k];
    }
    y[i] = s / l[i][i];
  }
  final x = List<double>.filled(n, 0);
  for (var i = n - 1; i >= 0; i--) {
    var s = y[i];
    for (var k = i + 1; k < n; k++) {
      s -= l[k][i] * x[k];
    }
    x[i] = s / l[i][i];
  }
  return x;
}
