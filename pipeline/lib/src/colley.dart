import 'dart:math';

/// A head-to-head result between two teams, by index.
class Result {
  Result(this.a, this.b, this.scoreA, this.scoreB, {this.weight = 1, this.lossScale = 1});
  final int a;
  final int b;
  final int scoreA;
  final int scoreB;

  /// How much this game counts; 1 is a normal game.
  final double weight;

  /// How much of the loss the loser takes; below 1 softens a loss to a
  /// stronger class of team.
  final double lossScale;
}

/// How much of a win a result is worth, from 0.5 (a tie) to 1. A win is
/// worth at least [baseWin] and the rest grows with the run differential up
/// to [marginCap] runs, so winning matters most, winning big matters some,
/// and running up the score past the cap gains nothing.
const baseWin = 0.8, marginCap = 10;

double winShare(int scoreFor, int scoreAgainst) {
  final diff = scoreFor - scoreAgainst;
  if (diff == 0) return 0.5;
  final m = min(diff.abs(), marginCap) / marginCap;
  final win = baseWin + (1 - baseWin) * m;
  return diff > 0 ? win : 1 - win;
}

/// Colley Matrix ratings (Wesley Colley, 2002), with margin of victory.
///
/// Each team's rating is 0.5 plus half its net wins, adjusted by the ratings
/// of the teams it played. Solving the whole system at once means every
/// opponent's rating depends on its own opponents, and theirs on theirs, all
/// the way through the schedule: beating a team that beat good teams is
/// worth a lot, and beating a winless team is worth little. A win counts as
/// [winShare] of a win (0.8 for one run, a full win at 10 or more runs), and
/// the loser gets the rest. Ties count as half a win each.
///
/// Solves `C r = b` where `C[i][i] = 2 + games_i`, `C[i][j] = -games(i,j)` and
/// `b[i] = 1 + (wins_i - losses_i) / 2`, where a game's win and loss are
/// split by [winShare]. `C` is symmetric positive definite,
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
    // Net wins for A: 2 * share - 1, from -1 (a full loss) to 1 (a full win).
    final diff = w * (2 * winShare(r.scoreA, r.scoreB) - 1) / 2;
    b[r.a] += diff < 0 ? diff * r.lossScale : diff;
    b[r.b] -= diff > 0 ? diff * r.lossScale : diff;
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

/// Gives direct matchups extra weight on top of [ratings].
///
/// For every pair of teams that played, the team with more wins against the
/// other is the head-to-head winner. When the winner is rated below the
/// loser, the winner moves up and the loser down, each by [share] of the gap
/// (at most [cap]). With the defaults, a head-to-head winner within 0.10 of
/// the loser passes it; a bigger gap still shrinks by up to 0.12. Every
/// adjustment is computed from the original ratings, so the order of games
/// does not matter, and a team that beat several higher-rated teams gains
/// from each of them.
List<double> headToHeadAdjusted(List<double> ratings, List<Result> results,
    {double share = 0.6, double cap = 0.10}) {
  final net = <(int, int), int>{};
  for (final r in results) {
    if (r.a == r.b || r.scoreA == r.scoreB) continue;
    final (lo, hi) = r.a < r.b ? (r.a, r.b) : (r.b, r.a);
    final loWon = (r.scoreA > r.scoreB) == (r.a == lo);
    net[(lo, hi)] = (net[(lo, hi)] ?? 0) + (loWon ? 1 : -1);
  }
  final out = List<double>.of(ratings);
  net.forEach((pair, n) {
    if (n == 0) return;
    final (winner, loser) = n > 0 ? pair : (pair.$2, pair.$1);
    final gap = ratings[loser] - ratings[winner];
    if (gap <= 0) return;
    final move = share * min(gap, cap);
    out[winner] += move;
    out[loser] -= move;
  });
  return out;
}
