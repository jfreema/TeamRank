import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../http.dart';
import '../model.dart';
import '../season.dart';
import 'otc.dart';

/// Grand Slam Sports Tournaments, grandslamtournaments.com.
///
/// Runs on the same site software as OTC, with three differences that matter
/// here: there is no list of past events, team pages group games under one
/// tab per event, and hometowns read `GA - Decatur`.
///
/// Event IDs count up as events are created, so the scraper walks every ID
/// from the first one of the season and keeps a record of each, even the
/// ones it skips, so later runs only look at new IDs. It collects:
/// - every Louisiana event with divisions in the covered ages, with all its games;
/// - games Louisiana teams played at Grand Slam events in other states,
///   read from those teams' pages.
class GrandSlamScraper {
  GrandSlamScraper(this.client, {this.base = 'https://grandslamtournaments.com', this.state = 'LA'});

  static const source = 'gs';
  final PoliteClient client;
  final String base;
  final String state;

  /// Stop looking for older events after this many IDs in a row that are
  /// missing or from an earlier season.
  static const _floorRun = 60;

  /// Reads new and unfinished events into [cache]. With [refetch], every
  /// saved event is looked at again too (after the covered ages change).
  Future<void> scrape(SourceCache cache, Season season, DateTime today,
      {bool refetch = false, void Function(String) log = print}) async {
    // Newest IDs come from the upcoming events list.
    final listed = <int>{};
    for (var page = 1; page <= 10; page++) {
      final body = await client.get('$base/baseball/Events?page=$page');
      final ids = RegExp(r'Events/Details/(\d+)/').allMatches(body).map((m) => int.parse(m.group(1)!)).toSet();
      if (ids.difference(listed).isEmpty) break;
      listed.addAll(ids);
    }
    if (listed.isEmpty) throw StateError('no events listed');
    final known = cache.events.keys.map(int.parse).toSet();
    final top = listed.reduce((a, b) => a > b ? a : b);

    Future<void> look(int id) async {
      final ev = await _event(id, season, today, log);
      cache.events['$id'] = ev ?? _skipped(id);
    }

    if (known.isEmpty) {
      // First run: walk down from the newest ID until the season's start.
      var misses = 0;
      for (var id = top; id > 0 && misses < _floorRun; id--) {
        await look(id);
        final ev = cache.events['$id']!;
        // Pages give no year, so a date far ahead is most likely last season.
        final start = ev.startDate.isEmpty ? null : DateTime.parse(ev.startDate);
        final current = start != null &&
            (season.contains(start) || start.difference(today).inDays.abs() < 120);
        misses = current ? 0 : misses + 1;
      }
    } else {
      if (refetch) {
        // Louisiana events are read again below and keep their saved games
        // until then. Other events keep theirs until Louisiana teams' pages
        // are read. An event that cannot be looked at stays as it was.
        for (final old in cache.events.values.toList()) {
          final ev = await _event(int.parse(old.id), season, today, log);
          if (ev == null) continue;
          cache.events[old.id] = EventRecord(
              id: ev.id,
              name: ev.isFinal ? old.name : ev.name,
              startDate: ev.startDate,
              endDate: ev.endDate,
              isFinal: ev.isFinal,
              games: old.games,
              teamKeys: old.teamKeys);
        }
      }
      final newest = known.reduce((a, b) => a > b ? a : b);
      for (var id = newest + 1; id <= top; id++) {
        await look(id);
      }
      // Events that had not finished yet (when refetching, all were just looked at).
      // Away events are rebuilt from team pages below.
      for (final ev in cache.events.values.where((e) => !refetch && !e.isFinal && e.startDate.isNotEmpty).toList()) {
        if (!DateTime.parse(ev.startDate).isAfter(today)) await look(int.parse(ev.id));
      }
    }

    // Teams at Louisiana events that are not final, plus every Louisiana team
    // (for its games at events in other states).
    final open = cache.events.values.where((e) => !e.isFinal && e.startDate.isNotEmpty &&
        !DateTime.parse(e.startDate).isAfter(today));
    final eventTeams = <String, Set<String>>{};
    for (final ev in open) {
      if (ev.name.isEmpty) continue;
      final teams = <String>{};
      final details = await client.get('$base/baseball/Events/Details/${ev.id}');
      for (final d in OtcScraper.parseDivisions(details).where(OtcScraper.isAgeDivision)) {
        teams.addAll(OtcScraper.parseTeamIds(await client.get(
            '$base/baseball/Events/Schedule/${ev.id}/x?division=${Uri.encodeQueryComponent(d)}')));
      }
      eventTeams[ev.id] = teams;
    }
    final home = {
      for (final t in cache.teams.values)
        if (t.state == state) t.key.substring(source.length + 1)
    };

    final pages = <String, GsTeamPage>{};
    Future<void> fetch(String id) async {
      if (pages.containsKey(id)) return;
      try {
        pages[id] = parseTeamPage(await client.get('$base/baseball/Teams/Details/$id/team'), id);
        cache.teams['$source:$id'] = pages[id]!.team;
      } catch (e) {
        log('gs: team $id failed: $e');
      }
    }

    for (final id in {...eventTeams.values.expand((t) => t), ...home}) {
      await fetch(id);
    }

    // Every game at a Louisiana event, and Louisiana teams' games elsewhere.
    final byEvent = <String, List<GsTeamPage>>{};
    for (final p in pages.values) {
      for (final eid in p.events.keys) {
        if (eventTeams.containsKey(eid) || p.team.state == state) {
          byEvent.putIfAbsent(eid, () => []).add(p);
        }
      }
    }
    // Opponents never seen before, such as bracket opponents.
    final opponents = {
      for (final e in byEvent.entries)
        for (final p in e.value)
          for (final g in p.games.where((g) => g.eventId == e.key)) ...[g.teamA, g.teamB]
    }.where((id) => !cache.teams.containsKey('$source:$id'));
    for (final id in opponents.toList()) {
      await fetch(id);
      if (!cache.teams.containsKey('$source:$id')) {
        final name = pages.values.map((p) => p.names[id]).whereType<String>().firstOrNull ?? id;
        cache.teams['$source:$id'] = SourceTeam(key: '$source:$id', name: name);
      }
    }
    var added = 0;
    byEvent.forEach((eid, list) {
      final old = cache.events[eid];
      // Finished events keep their saved games, unless refetching.
      if (!refetch && old != null && old.isFinal && old.games.isNotEmpty) return;
      final info = list.first.events[eid]!;
      if (!season.contains(info.start) || !OtcScraper.isAgeDivision(info.division)) return;
      final games = collectEventGames(eid, info.name, list);
      final end = info.start.add(Duration(days: info.lengthDays - 1));
      cache.events[eid] = EventRecord(
        id: eid,
        name: info.name,
        startDate: isoDate(info.start),
        endDate: isoDate(end),
        isFinal: isEventFinal(isoDate(end), today),
        teamKeys: [for (final t in eventTeams[eid] ?? <String>{}) '$source:$t']..sort(),
        games: games,
      );
      added += games.length;
    });
    // Louisiana events that are over but had no games, such as rainouts.
    for (final eid in eventTeams.keys.where((e) => !byEvent.containsKey(e))) {
      final ev = cache.events[eid]!;
      if (ev.endDate.isNotEmpty && isEventFinal(ev.endDate, today)) {
        cache.events[eid] = EventRecord(
            id: eid, name: ev.name, startDate: ev.startDate, endDate: ev.endDate,
            isFinal: true, games: [], teamKeys: ev.teamKeys);
      }
    }
    log('gs: ${cache.events.length} event IDs known, ${pages.length} team pages read, $added games refreshed');
  }

  /// Reads one event's details page. Null when it does not exist.
  /// Events outside [state] or without divisions in the covered ages are kept as
  /// final records with no games, so they are not fetched again.
  Future<EventRecord?> _event(int id, Season season, DateTime today, void Function(String) log) async {
    String body;
    try {
      body = await client.get('$base/baseball/Events/Details/$id');
    } catch (_) {
      return null;
    }
    final info = parseEventDetails(body, today);
    if (info == null) return null;
    final wanted = info.state == state && OtcScraper.parseDivisions(body).any(OtcScraper.isAgeDivision);
    final start = info.start;
    final end = start?.add(Duration(days: info.lengthDays - 1));
    return EventRecord(
      id: '$id',
      name: wanted ? info.name : '',
      startDate: start == null ? '' : isoDate(start),
      endDate: end == null ? '' : isoDate(end),
      // Louisiana events stay open until their games are read.
      isFinal: !wanted,
      games: [],
      // Marks a Louisiana event; filled with team keys once read.
      teamKeys: const [],
    );
  }

  static EventRecord _skipped(int id) => EventRecord(
      id: '$id', name: '', startDate: '', endDate: '', isFinal: true, games: [], teamKeys: []);

  /// Name, state and dates from an event's details page.
  static GsEventInfo? parseEventDetails(String body, DateTime today) {
    final doc = html.parse(body);
    final group = doc.querySelector('hgroup');
    if (group == null) return null;
    final h3 = group.querySelectorAll('h3').map(_text).toList();
    final name = _text(group.querySelector('h1'));
    final place = h3.isEmpty ? '' : h3.first;
    final st = RegExp(r',\s*([A-Z]{2})\b').allMatches(place).lastOrNull?.group(1) ?? '';
    final (start, length) = OtcScraper.parseListingDate(h3.isEmpty ? '' : h3.last, today);
    return GsEventInfo(name: name, state: st, start: start, lengthDays: length);
  }

  static GsTeamPage parseTeamPage(String body, String id) {
    final doc = html.parse(body);
    final header = doc.querySelector('#team-details .row-header');
    final location = _text(header?.querySelector('.h3'));
    final m = RegExp(r'^([A-Za-z]{2})\s*-\s*(.*)$').firstMatch(location);
    final loc = location.split(',');
    final (city, st) = m != null
        ? (m.group(2)!.trim(), m.group(1)!.toUpperCase())
        : (loc.first.trim(), loc.length > 1 ? loc[1].trim().toUpperCase() : '');
    final logo = header?.querySelector('img')?.attributes['src'] ?? '';
    final team = SourceTeam(
      key: '$source:$id',
      name: _text(header?.querySelector('.h1')),
      city: city,
      state: st,
      ageClass: _text(header?.querySelector('.h4')),
      url: 'https://grandslamtournaments.com/baseball/Teams/Details/$id',
      logo: logo.isEmpty || logo.contains('silhouette') || logo.contains('no-image')
          ? ''
          : Uri.parse('https://grandslamtournaments.com/').resolve(logo).toString(),
    );

    // Event summary rows: event ID, start date and division.
    final summary = <String, (DateTime, String, String)>{};
    for (final row in doc.querySelectorAll('tr')) {
      final link = row.querySelector('a[href*="Events/Details/"]');
      final date = row.querySelector('td[data-title="Start Date"]');
      final div = row.querySelector('td[data-title="Division"]');
      if (link == null || date == null || div == null) continue;
      final d = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(_text(date));
      if (d == null) continue;
      final eid = RegExp(r'Events/Details/(\d+)').firstMatch(link.attributes['href']!)!.group(1)!;
      summary[eid] = (
        DateTime(int.parse(d.group(3)!), int.parse(d.group(1)!), int.parse(d.group(2)!)),
        _text(div),
        _text(link),
      );
    }

    final events = <String, GsTeamEvent>{};
    final games = <OtcTeamGame>[];
    final names = <String, String>{};
    for (final pane in doc.querySelectorAll('div.tab-pane[id^="eventTeam-"]')) {
      final title = _text(pane.querySelector('.pt'));
      final division = _text(pane.querySelector('.page-header small'));
      final match = summary.entries
          .where((e) => e.value.$3 == title && e.value.$2 == division)
          .firstOrNull;
      if (match == null) continue;
      final (start, _, name) = match.value;
      final dates = pane.querySelectorAll('.page-header small').map(_text).toList();
      final (_, length) = OtcScraper.parseListingDate(dates.length > 1 ? dates[1] : '', start);
      events[match.key] = GsTeamEvent(name, start, length, division);
      for (final row in pane.querySelectorAll('tr')) {
        final links = row.querySelectorAll('a[href*="Teams/Details/"]');
        final score = row
            .querySelectorAll('td')
            .map(_text)
            .map(RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch)
            .whereType<RegExpMatch>()
            .firstOrNull;
        if (links.length != 2 || score == null) continue;
        final ids = [
          for (final a in links) RegExp(r'Teams/Details/(\d+)').firstMatch(a.attributes['href']!)!.group(1)!
        ];
        for (var i = 0; i < 2; i++) {
          names[ids[i]] = _text(links[i]);
        }
        games.add(OtcTeamGame(
          eventId: match.key,
          teamA: ids[0],
          teamB: ids[1],
          scoreA: int.parse(score.group(1)!),
          scoreB: int.parse(score.group(2)!),
        ));
      }
    }
    return GsTeamPage(team, events, games, names);
  }

  /// Games of one event across [pages], each counted as many times as the
  /// page that lists it the most (two teams can meet twice in one event).
  static List<Game> collectEventGames(String eventId, String eventName, Iterable<GsTeamPage> pages) {
    final counts = <String, int>{};
    final samples = <String, (OtcTeamGame, GsTeamEvent)>{};
    for (final p in pages) {
      final ev = p.events[eventId];
      if (ev == null) continue;
      final seen = <String, int>{};
      for (final g in p.games.where((g) => g.eventId == eventId)) {
        seen[g.canonicalKey] = (seen[g.canonicalKey] ?? 0) + 1;
        samples[g.canonicalKey] ??= (g, ev);
      }
      seen.forEach((k, n) {
        if (n > (counts[k] ?? 0)) counts[k] = n;
      });
    }
    return [
      for (final k in counts.keys.toList()..sort())
        for (var i = 0; i < counts[k]!; i++)
          Game(
            source: source,
            eventId: eventId,
            eventName: eventName,
            date: isoDate(samples[k]!.$2.start),
            division: samples[k]!.$2.division,
            teamA: '$source:${samples[k]!.$1.teamA}',
            teamB: '$source:${samples[k]!.$1.teamB}',
            scoreA: samples[k]!.$1.scoreA,
            scoreB: samples[k]!.$1.scoreB,
          )
    ];
  }

  static String _text(Element? e) => (e?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

class GsEventInfo {
  GsEventInfo({required this.name, required this.state, required this.start, required this.lengthDays});
  final String name;
  final String state;
  final DateTime? start;
  final int lengthDays;
}

class GsTeamEvent {
  GsTeamEvent(this.name, this.start, this.lengthDays, this.division);
  final String name;
  final DateTime start;
  final int lengthDays;
  final String division;
}

class GsTeamPage {
  GsTeamPage(this.team, this.events, this.games, this.names);
  final SourceTeam team;
  final Map<String, GsTeamEvent> events;
  final List<OtcTeamGame> games;

  /// Team names as linked in the game rows, by team ID.
  final Map<String, String> names;
}
