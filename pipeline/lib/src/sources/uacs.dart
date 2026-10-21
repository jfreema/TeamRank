import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../http.dart';
import '../identity.dart';
import '../model.dart';
import '../season.dart';
import 'otc.dart';

/// UACS Sports, www.uacssports.com (runs on TeamSideline).
///
/// The schedules page lists each tournament's divisions while they are
/// active; each division page has the standings, the pool and playoff games
/// and their scores. Once a tournament is over, UACS switches its divisions
/// off and the scores are no longer public, so every run saves what is
/// listed and the cache keeps it after that.
///
/// Teams have no ID or hometown on the site. A listing is keyed by its name
/// and age, and its state is the state of the fields it played on.
class UacsScraper {
  UacsScraper(this.client, {this.base = 'https://www.uacssports.com'});

  static const source = 'uacs';
  final PoliteClient client;
  final String base;

  Future<void> scrape(SourceCache cache, Season season, DateTime today,
      {void Function(String) log = print}) async {
    final divisions = parseScheduleLinks(await client.get('$base/schedules'));
    var games = 0;
    for (final d in divisions) {
      final old = cache.events[d.id];
      if (old != null && old.isFinal) continue;
      final page = parseDivision(await client.get('$base/schedule/${d.id}/${d.slug}'), d.id, season);
      if (page == null || !OtcScraper.isAgeDivision(page.division)) continue;
      for (final t in page.teams) {
        t.url = '$base/schedule/${d.id}/${d.slug}';
        final known = cache.teams[t.key];
        if (known != null && t.state.isEmpty) t.state = known.state;
        cache.teams[t.key] = t;
      }
      // Keep earlier scores if the page no longer shows them.
      if (page.games.isEmpty && old != null && old.games.isNotEmpty) continue;
      final dates = page.games.map((g) => g.date).toList()..sort();
      final end = dates.isEmpty ? '' : dates.last;
      cache.events[d.id] = EventRecord(
        id: d.id,
        name: page.event,
        startDate: dates.isEmpty ? '' : dates.first,
        endDate: end,
        isFinal: end.isNotEmpty && isEventFinal(end, today),
        teamKeys: [for (final t in page.teams) t.key]..sort(),
        games: page.games,
      );
      games += page.games.length;
    }
    log('uacs: ${divisions.length} divisions listed, $games games read');
  }

  /// Division links on the schedules page, like `/schedule/728425/12u-Open`.
  static List<({String id, String slug})> parseScheduleLinks(String body) {
    final seen = <String>{};
    return [
      for (final m in RegExp(r'schedule/(\d+)/([^"?#/]+)', caseSensitive: false).allMatches(body))
        if (seen.add(m.group(1)!)) (id: m.group(1)!, slug: m.group(2)!)
    ];
  }

  /// One division page: its tournament, the teams that played and the
  /// finished games. Null when the division has been switched off.
  static UacsDivision? parseDivision(String body, String id, Season season) {
    final doc = html.parse(body);
    final event = _text(doc.querySelector('#TitlePanel h1'));
    final division = _text(doc.querySelector('#PageSubTitleSpan'));
    if (event.isEmpty || body.contains('de-activated the Standings')) return null;
    final age = ageOf(division);

    final teams = <String, SourceTeam>{};
    SourceTeam team(String name, String state) {
      final key = '$source:${normalizeTeamName(name).replaceAll(' ', '-')}|${age ?? ''}';
      final t = teams.putIfAbsent(key, () => SourceTeam(key: key, name: name, ageClass: division));
      if (t.state.isEmpty) t.state = state;
      return t;
    }

    final games = <Game>[];
    final seen = <String>{};
    // The mobile grids hold the same games as the desktop ones, with the
    // scores and field in one cell.
    for (final row in doc.querySelectorAll(
        '[id\$="MobileScheduleGrid"] tr, [id\$="MobilePlayoffGrid"] tr')) {
      String part(String name) => _text(row.querySelector('[id\$="_$name"]'));
      final home = part('HomeLabel'), away = part('AwayLabel');
      final hs = int.tryParse(part('HomeScoreLabel')), as = int.tryParse(part('AwayScoreLabel'));
      final date = _date(part('DateLabel'), season);
      if (home.isEmpty || away.isEmpty || hs == null || as == null || date == null) continue;
      final where = Uri.decodeFull(row.querySelector('[id\$="_LocationLink"]')?.attributes['href'] ?? '');
      final state = RegExp(r',\s*([A-Z]{2})\s+\d{5}').firstMatch(where)?.group(1) ?? '';
      final key = '$date|${part('TimeLabel')}|$home|$away|${part('LocationLabel')}';
      if (!seen.add(key)) continue;
      games.add(Game(
        source: source,
        eventId: id,
        eventName: event,
        date: date,
        division: division,
        teamA: team(home, state).key,
        teamB: team(away, state).key,
        scoreA: hs,
        scoreB: as,
      ));
    }
    return UacsDivision(event, division, teams.values.toList(), games);
  }

  /// `Sat 10/24` in [season]: August to December is the first year.
  static String? _date(String label, Season season) {
    final m = RegExp(r'(\d{1,2})/(\d{1,2})').firstMatch(label);
    if (m == null) return null;
    final month = int.parse(m.group(1)!), day = int.parse(m.group(2)!);
    final year = month >= season.start.month ? season.start.year : season.end.year;
    return isoDate(DateTime(year, month, day));
  }

  static String _text(Element? e) => (e?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

class UacsDivision {
  UacsDivision(this.event, this.division, this.teams, this.games);
  final String event;
  final String division;
  final List<SourceTeam> teams;
  final List<Game> games;
}
