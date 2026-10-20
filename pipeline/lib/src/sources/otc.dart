import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../http.dart';
import '../model.dart';
import '../season.dart';

/// OTC Sports (Off The Cross Sports), offthecrosssports.com.
///
/// Every page is plain server-rendered HTML. Each team has a stable numeric ID
/// and a team page listing its hometown, every event it played (with the
/// event date and division) and every game score, including bracket games.
/// So the scraper finds the 12U teams of each event from the division
/// schedule, then reads the games off those team pages.
class OtcScraper {
  OtcScraper(this.client, {this.base = 'https://offthecrosssports.com'});

  static const source = 'otc';
  final PoliteClient client;
  final String base;

  Future<void> scrape(SourceCache cache, Season season, DateTime today,
      {void Function(String) log = print}) async {

    final listings = <String, OtcListing>{};
    for (final l in parseListings(await client.get('$base/baseball/Events'),
        today: today)) {
      listings[l.id] = l;
    }
    for (var page = 1; page <= 25; page++) {
      final found = parseListings(
          await client.get('$base/Baseball/Events/Previous?page=$page'),
          today: today);
      final fresh = found.where((l) => !listings.containsKey(l.id)).toList();
      for (final l in fresh) {
        listings[l.id] = l;
      }
      // Pages run newest to oldest. Stop once a whole page is before the season.
      final dated = fresh.where((l) => l.start != null).toList();
      if (fresh.isEmpty ||
          (dated.isNotEmpty && dated.every((l) => l.start!.isBefore(season.start)))) {
        break;
      }
    }

    final todo = listings.values.where((l) {
      if (!l.has12U) return false;
      if (l.start != null && (!season.contains(l.start!) || l.start!.isAfter(today))) {
        return false;
      }
      return !(cache.events[l.id]?.isFinal ?? false);
    }).toList();
    log('otc: ${listings.length} events listed, ${todo.length} 12U events to fetch');
    if (todo.isNotEmpty) await _scrapeEvents(cache, todo, today, log);

    // Teams saved before logos were collected.
    for (final t in cache.teams.values.where((t) => t.state == 'LA' && t.logo == null)) {
      try {
        final id = t.key.substring(source.length + 1);
        t.logo = parseTeamPage(await client.get('$base/Baseball/Teams/Details/$id/team'), id).team.logo;
      } catch (e) {
        log('otc: logo for ${t.key} failed: $e');
      }
    }
  }

  Future<void> _scrapeEvents(SourceCache cache, List<OtcListing> todo, DateTime today,
      void Function(String) log) async {

    // 1. Which 12U teams played in each event.
    final eventTeams = <String, Set<String>>{};
    for (final l in todo) {
      final details = await client.get('$base/Baseball/Events/Details/${l.id}/${l.slug}');
      final teams = <String>{};
      for (final division in parseDivisions(details).where(is12U)) {
        final sched = await client.get(
            '$base/Baseball/Events/Schedule/${l.id}/${l.slug}?division=${Uri.encodeQueryComponent(division)}');
        teams.addAll(parseTeamIds(sched));
      }
      eventTeams[l.id] = teams;
    }

    // 2. Team pages: hometown, events played and every game.
    final pages = <String, OtcTeamPage>{};
    Future<void> fetchTeam(String id) async {
      if (pages.containsKey(id)) return;
      try {
        pages[id] = parseTeamPage(
            await client.get('$base/Baseball/Teams/Details/$id/team'), id);
      } catch (e) {
        log('otc: team $id failed: $e');
      }
    }

    for (final id in eventTeams.values.expand((t) => t).toSet()) {
      await fetchTeam(id);
    }
    // Opponents that only showed up in bracket games.
    for (final id in pages.values
        .expand((p) => p.games)
        .where((g) => eventTeams.containsKey(g.eventId))
        .expand((g) => [g.teamA, g.teamB])
        .toSet()) {
      await fetchTeam(id);
    }

    for (final p in pages.values) {
      cache.teams[p.team.key] = p.team;
    }

    // 3. Assemble each event's games, de-duplicated across both teams' pages.
    for (final l in todo) {
      final games = collectEventGames(l, pages.values);
      final dates = pages.values
          .map((p) => p.events[l.id]?.date)
          .whereType<DateTime>()
          .toList()
        ..sort();
      final start = dates.isNotEmpty ? dates.first : l.start;
      if (start == null) continue;
      final end = start.add(Duration(days: l.lengthDays - 1));
      cache.events[l.id] = EventRecord(
        id: l.id,
        name: l.name,
        startDate: isoDate(start),
        endDate: isoDate(end),
        isFinal: isEventFinal(isoDate(end), today),
        teamKeys: (eventTeams[l.id]!.map((t) => '$source:$t').toList()..sort()),
        games: games,
      );
    }
  }

  static bool is12U(String division) =>
      division.toUpperCase().startsWith('12U');

  /// Events on an OTC events or past-events page.
  static List<OtcListing> parseListings(String body, {required DateTime today}) {
    final doc = html.parse(body);
    final out = <OtcListing>[];
    for (final media in doc.querySelectorAll('.media')) {
      final link = media.querySelector('.media-body .h4 a');
      final m = RegExp(r'Events/Details/(\d+)/([^/?#"]+)', caseSensitive: false)
          .firstMatch(link?.attributes['href'] ?? '');
      if (link == null || m == null) continue;
      final h4s = media
          .querySelectorAll('.media-body .h4')
          .where((e) => e.querySelector('a') == null)
          .map((e) => _text(e))
          .toList();
      final dateText = h4s.isEmpty ? '' : h4s.first;
      final ages = media.querySelectorAll('.media-body .h6').map(_text).join(' ');
      final (start, length) = parseListingDate(dateText, today);
      out.add(OtcListing(
        id: m.group(1)!,
        slug: m.group(2)!,
        name: _text(link),
        start: start,
        lengthDays: length,
        has12U: RegExp(r'\b12U', caseSensitive: false).hasMatch(ages),
      ));
    }
    return out;
  }

  /// Parses dates like `Oct 10-11`, `May 10-11, 2025` or `Sep 30-Oct 1`.
  /// When the year is missing, picks the year that puts the date nearest today.
  static (DateTime?, int) parseListingDate(String text, DateTime today) {
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final m = RegExp(
            r'([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2})(?:\s*-\s*(?:([A-Za-z]{3})[a-z]*\.?\s+)?(\d{1,2}))?(?:,\s*(\d{4}))?')
        .firstMatch(text);
    if (m == null) return (null, 2);
    final month = months[m.group(1)!.toLowerCase()];
    if (month == null) return (null, 2);
    final day = int.parse(m.group(2)!);
    final endMonth = m.group(3) == null ? month : months[m.group(3)!.toLowerCase()] ?? month;
    final endDay = m.group(4) == null ? day : int.parse(m.group(4)!);
    int year;
    if (m.group(5) != null) {
      year = int.parse(m.group(5)!);
    } else {
      year = today.year;
      if (DateTime(year, month, day).difference(today).inDays > 200) year--;
    }
    final start = DateTime(year, month, day);
    var end = DateTime(endMonth < month ? year + 1 : year, endMonth, endDay);
    if (end.isBefore(start)) end = start;
    return (start, end.difference(start).inDays + 1);
  }

  /// Division names (like `12U-AA`) linked from an event's details page.
  static List<String> parseDivisions(String body) {
    final doc = html.parse(body);
    final out = <String>{};
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href']!;
      if (!href.contains('/Events/Schedule/')) continue;
      final d = Uri.tryParse(href)?.queryParameters['division'];
      if (d != null && d.isNotEmpty) out.add(d);
    }
    return out.toList();
  }

  static Set<String> parseTeamIds(String body) => RegExp(r'Teams/Details/(\d+)/')
      .allMatches(body)
      .map((m) => m.group(1)!)
      .toSet();

  static OtcTeamPage parseTeamPage(String body, String id) {
    final doc = html.parse(body);
    final header = doc.querySelector('#team-details .row-header');
    final location = _text(header?.querySelector('.h3'));
    final name = _text(header?.querySelector('.h1'));
    final ageClass = _text(header?.querySelector('.h4'));
    final loc = location.split(',');
    final team = SourceTeam(
      key: '$source:$id',
      name: name,
      city: loc.first.trim(),
      state: loc.length > 1 ? loc[1].trim().toUpperCase() : '',
      ageClass: ageClass,
      url: 'https://offthecrosssports.com/Baseball/Teams/Details/$id',
      logo: parseLogo(doc.querySelector('img.center-block.img-responsive')?.attributes['src']),
    );

    final events = <String, OtcTeamEvent>{};
    final games = <OtcTeamGame>[];
    for (final row in doc.querySelectorAll('tr')) {
      final cells = row.querySelectorAll('td');
      final eventLink = row.querySelector('a[href*="Events/Details/"]');
      if (eventLink == null) continue;
      final eventId = RegExp(r'Events/Details/(\d+)')
          .firstMatch(eventLink.attributes['href']!)!
          .group(1)!;

      final dateCell = cells.where((c) => c.attributes['data-title'] == 'Start Date');
      final divCell = cells.where((c) => c.attributes['data-title'] == 'Division');
      if (dateCell.isNotEmpty && divCell.isNotEmpty) {
        final d = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(_text(dateCell.first));
        if (d != null) {
          events[eventId] = OtcTeamEvent(
            DateTime(int.parse(d.group(3)!), int.parse(d.group(1)!), int.parse(d.group(2)!)),
            _text(divCell.first),
          );
        }
        continue;
      }

      final teamIds = row
          .querySelectorAll('a[href*="Teams/Details/"]')
          .map((a) => RegExp(r'Teams/Details/(\d+)').firstMatch(a.attributes['href']!)!.group(1)!)
          .toList();
      final score = RegExp(r'^(\d+)\s*-\s*(\d+)$');
      final scoreCell = cells
          .map((c) => _text(c))
          .map(score.firstMatch)
          .whereType<RegExpMatch>()
          .firstOrNull;
      if (teamIds.length != 2 || scoreCell == null) continue;
      games.add(OtcTeamGame(
        eventId: eventId,
        teamA: teamIds[0],
        teamB: teamIds[1],
        scoreA: int.parse(scoreCell.group(1)!),
        scoreB: int.parse(scoreCell.group(2)!),
      ));
    }
    return OtcTeamPage(team, events, games);
  }

  /// The team logo, or '' for OTC's "no image available" placeholder.
  static String parseLogo(String? src) {
    if (src == null || src.isEmpty || src.contains('no-image-available')) return '';
    return Uri.parse('https://offthecrosssports.com/').resolve(src).toString();
  }

  /// Games of event [l] as seen across [pages]. Both teams' pages list the
  /// same game, so each distinct result counts as many times as the page that
  /// lists it the most (two teams can meet twice in one event).
  static List<Game> collectEventGames(OtcListing l, Iterable<OtcTeamPage> pages) {
    final counts = <String, int>{};
    final samples = <String, (OtcTeamGame, String, DateTime)>{};
    for (final p in pages) {
      final ev = p.events[l.id];
      if (ev == null || !is12U(ev.division)) continue;
      final seen = <String, int>{};
      for (final g in p.games.where((g) => g.eventId == l.id)) {
        final k = g.canonicalKey;
        seen[k] = (seen[k] ?? 0) + 1;
        samples[k] ??= (g, ev.division, ev.date);
      }
      seen.forEach((k, n) {
        if (n > (counts[k] ?? 0)) counts[k] = n;
      });
    }
    final out = <Game>[];
    for (final k in counts.keys.toList()..sort()) {
      final (g, division, date) = samples[k]!;
      for (var i = 0; i < counts[k]!; i++) {
        out.add(Game(
          source: source,
          eventId: l.id,
          eventName: l.name,
          date: isoDate(date),
          division: division,
          teamA: '$source:${g.teamA}',
          teamB: '$source:${g.teamB}',
          scoreA: g.scoreA,
          scoreB: g.scoreB,
        ));
      }
    }
    return out;
  }

  static String _text(Element? e) =>
      (e?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

class OtcListing {
  OtcListing({
    required this.id,
    required this.slug,
    required this.name,
    required this.start,
    required this.lengthDays,
    required this.has12U,
  });

  final String id;
  final String slug;
  final String name;
  final DateTime? start;
  final int lengthDays;
  final bool has12U;
}

class OtcTeamEvent {
  OtcTeamEvent(this.date, this.division);
  final DateTime date;
  final String division;
}

class OtcTeamGame {
  OtcTeamGame({
    required this.eventId,
    required this.teamA,
    required this.teamB,
    required this.scoreA,
    required this.scoreB,
  });

  final String eventId;
  final String teamA;
  final String teamB;
  final int scoreA;
  final int scoreB;

  /// The same game seen from either team's page gives the same key.
  String get canonicalKey => teamA.compareTo(teamB) <= 0
      ? '$teamA|$teamB|$scoreA|$scoreB'
      : '$teamB|$teamA|$scoreB|$scoreA';
}

class OtcTeamPage {
  OtcTeamPage(this.team, this.events, this.games);
  final SourceTeam team;
  final Map<String, OtcTeamEvent> events;
  final List<OtcTeamGame> games;
}
