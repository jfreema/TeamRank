import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../http.dart';
import '../identity.dart';
import '../model.dart';
import '../season.dart';

/// 2D Sports, youth.2dsports.org (runs on Playbook365).
///
/// The past-events list and each division's schedule come from JSON
/// endpoints the site's own pages call (`/ajax-events`, `/schedule_ajax`),
/// guarded by a Laravel CSRF token. Teams have a UUID per season, and the
/// standings feed includes each team's home state.
class TwoDScraper {
  TwoDScraper(this.client, {this.base = 'https://youth.2dsports.org'});

  static const source = '2d';
  final PoliteClient client;
  final String base;

  Future<void> scrape(SourceCache cache, Season season, DateTime today,
      {void Function(String) log = print}) async {
    var token = await _csrf();

    final events = <Map<String, dynamic>>[];
    for (var page = 1; page <= 40; page++) {
      final res = jsonDecode(await client.post('$base/ajax-events', headers: {
        'X-Requested-With': 'XMLHttpRequest',
        'X-CSRF-TOKEN': token,
        'Referer': '$base/past-events',
      }, body: {
        'page': '$page',
        'layout': 'small',
        'past_events': 'true',
        'events_exits': '',
        'organization_id': '',
        '_token': token,
      })) as Map<String, dynamic>;
      final list = (res['eventlist'] as List? ?? []).cast<Map<String, dynamic>>();
      if (list.isEmpty) break;
      events.addAll(list);
      final dates = list.map((e) => DateTime.tryParse('${e['start_date']}')).whereType<DateTime>();
      if (dates.isNotEmpty && dates.every((d) => d.isBefore(season.start))) break;
    }

    final todo = events.where((e) {
      final start = DateTime.tryParse('${e['start_date']}');
      if (start == null || !season.contains(start) || start.isAfter(today)) return false;
      return !(cache.events['${e['id']}']?.isFinal ?? false);
    }).toList();
    log('2d: ${events.length} past events listed, ${todo.length} to fetch');

    for (final e in todo) {
      final id = '${e['id']}';
      final key = '${e['url_key']}';
      final name = '${e['name']}';
      final endDate = '${e['end_date'] ?? e['start_date']}';
      try {
        // The schedule page links each division; each division page embeds
        // the ids its schedule feed needs.
        final page = await client.get('$base/events/$key/schedule');
        token = _metaToken(page) ?? token;
        final divisions = <TwoDDivision>[];
        for (final slug in parseDivisionLinks(page, key).where(isAgeDivision)) {
          final divPage = await client.get('$base/events/$key/$slug');
          token = _metaToken(divPage) ?? token;
          divisions.addAll(parseDivisions(divPage)
              .where((d) => d.urlKey == slug && isAgeDivision(d.label))
              .where((d) => divisions.every((x) => x.eventPriceId != d.eventPriceId)));
        }
        final games = <Game>[];
        final teamKeys = <String>{};
        // A crossover game between two divisions shows in both schedules.
        final seenGameIds = <String>{};
        if (divisions.isNotEmpty) {
          final hometowns = parseTeamHometowns(await client.get('$base/events/$key/teams'));
          for (final d in divisions) {
            Future<dynamic> feed(String type) => client.postJson('$base/schedule_ajax',
                headers: {
                  'X-Requested-With': 'XMLHttpRequest',
                  'X-CSRF-TOKEN': token,
                  'Referer': '$base/events/$key/${d.urlKey}',
                },
                body: {
                  'event_id': id,
                  'event_price_id': '${d.eventPriceId}',
                  'event_registration_item_id': '0',
                  'schedule_id': d.scheduleId,
                  'data_type': type,
                });
            final standings = await feed('standings');
            for (final t in parseStandingsTeams(standings)) {
              final home = hometowns[t.uuid];
              final k = '$source:${t.uuid}';
              cache.teams[k] = SourceTeam(
                key: k,
                name: t.name,
                city: home?.city ?? cache.teams[k]?.city ?? '',
                state: t.state.isNotEmpty ? t.state : (home?.state ?? ''),
                ageClass: home?.ageClass ?? d.label,
                url: '$base/team/details/${season.label}-season/${t.uuid}',
                logo: cache.teams[k]?.logo,
              );
              teamKeys.add(k);
            }
            final parsed = parseScheduleGames(await feed('schedules'),
                eventId: id, eventName: name, division: d.label);
            for (final (:id, :game, :nameA, :nameB) in parsed) {
              if (id.isNotEmpty && !seenGameIds.add(id)) continue;
              for (final (k, n) in [(game.teamA, nameA), (game.teamB, nameB)]) {
                teamKeys.add(k);
                cache.teams.putIfAbsent(k, () {
                  final home = hometowns[k.substring(source.length + 1)];
                  return SourceTeam(
                    key: k,
                    name: n,
                    city: home?.city ?? '',
                    state: home?.state ?? '',
                    ageClass: d.label,
                  );
                });
              }
              games.add(game);
            }
          }
        }
        cache.events[id] = EventRecord(
          id: id,
          name: name,
          startDate: '${e['start_date']}',
          endDate: endDate,
          isFinal: isEventFinal(endDate, today),
          teamKeys: teamKeys.toList()..sort(),
          games: games,
        );
      } catch (err) {
        log('2d: event $id ($key) failed: $err');
      }
    }

    // Logos are only on team pages, so fetch each Louisiana team's page once.
    for (final t in cache.teams.values.where((t) => t.state == 'LA' && t.logo == null && t.url.isNotEmpty)) {
      try {
        t.logo = parseTeamLogo(await client.get(t.url));
      } catch (err) {
        log('2d: logo for ${t.key} failed: $err');
      }
    }
  }

  /// The logo on a 2D team page, or '' when it shows 2D's own logo instead.
  static String parseTeamLogo(String page) {
    final src = html.parse(page).querySelector('.team-logo-content img')?.attributes['src'] ?? '';
    if (src.isEmpty || src.contains('/themes/')) return '';
    return src;
  }

  Future<String> _csrf() async {
    final res = jsonDecode(await client.get('$base/refresh-csrf',
        headers: {'X-Requested-With': 'XMLHttpRequest'})) as Map<String, dynamic>;
    return '${res['csrf_token']}';
  }

  static String? _metaToken(String page) =>
      RegExp(r'name="csrf-token" content="([^"]+)"').firstMatch(page)?.group(1);

  /// An age-group division such as `12u AA` (url key `12u-aa-`).
  static bool isAgeDivision(String label) => inAgeRange(ageOf(label.replaceAll('-', ' ')));

  /// Division url keys (like `12u-aa-`) linked from an event's schedule page.
  static List<String> parseDivisionLinks(String page, String eventKey) {
    final re = RegExp('/events/${RegExp.escape(eventKey)}/([^"/?#]+)"');
    const pages = {'schedule', 'teams', 'venues', 'facebook', 'twitter', 'copylink', 'rules', 'info'};
    return re
        .allMatches(page)
        .map((m) => m.group(1)!)
        .where((s) => !pages.contains(s))
        .toSet()
        .toList();
  }

  /// Reads the `window.DIVISIONS = {...}` object embedded in division pages.
  static List<TwoDDivision> parseDivisions(String page) {
    final json = extractJsonAssignment(page, 'window.DIVISIONS');
    if (json is! Map) return [];
    return json.values
        .whereType<Map>()
        .map((d) => TwoDDivision(
              eventPriceId: d['event_price_id'] as int,
              scheduleId: d['schedule_id'],
              label: '${d['label']}'.trim(),
              urlKey: '${d['url_key']}',
            ))
        .toList();
  }

  /// Finds `name = <json>` in a script and decodes the balanced JSON value.
  static dynamic extractJsonAssignment(String text, String name) {
    final at = text.indexOf('$name =');
    if (at < 0) return null;
    final start = text.indexOf(RegExp(r'[\[{]'), at);
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (c == r'\') {
          i++;
        } else if (c == '"') {
          inString = false;
        }
      } else if (c == '"') {
        inString = true;
      } else if (c == '{' || c == '[') {
        depth++;
      } else if (c == '}' || c == ']') {
        depth--;
        if (depth == 0) return jsonDecode(text.substring(start, i + 1));
      }
    }
    return null;
  }

  /// Team UUID -> hometown, from an event's `/teams` page, where each team
  /// shows as `Name` followed by `City, ST | (12u AA)`.
  static Map<String, TwoDHometown> parseTeamHometowns(String page) {
    final doc = html.parse(page);
    final out = <String, TwoDHometown>{};
    for (final a in doc.querySelectorAll('a[href*="/team/details/"]')) {
      final m = RegExp(r'/team/details/[^/]+/([0-9a-f\-]{36})')
          .firstMatch(a.attributes['href']!);
      if (m == null) continue;
      final small = a.parent?.parent?.querySelector('small');
      final text = (small?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      final loc = RegExp(r'^(.*?),\s*([A-Z]{2})\s*(?:\|\s*\((.*?)\))?').firstMatch(text);
      if (loc == null) continue;
      out[m.group(1)!] = TwoDHometown(
        loc.group(1)!.trim(),
        loc.group(2)!,
        (loc.group(3) ?? '').replaceAll(RegExp(r'\s+'), ' ').trim(),
      );
    }
    return out;
  }

  static List<TwoDStandingTeam> parseStandingsTeams(dynamic feed) {
    final out = <TwoDStandingTeam>[];
    for (final pool in (feed is Map ? feed['standings'] as List? ?? [] : [])) {
      for (final t in (pool as Map)['teams'] as List? ?? []) {
        final m = t as Map;
        final uuid = '${m['team_uuid'] ?? ''}';
        if (uuid.isEmpty) continue;
        out.add(TwoDStandingTeam(uuid, '${m['team_name']}'.trim(), '${m['team_state'] ?? ''}'));
      }
    }
    return out;
  }

  /// Final, non-exhibition games in a `schedules` feed, with the team names
  /// as listed (for teams missing from the standings).
  static List<({String id, Game game, String nameA, String nameB})> parseScheduleGames(dynamic feed,
      {required String eventId, required String eventName, required String division}) {
    final out = <({String id, Game game, String nameA, String nameB})>[];
    final days = feed is Map ? feed['schedules'] : null;
    if (days is! Map) return out;
    for (final day in days.values) {
      final teams = (day as Map)['teams'];
      final list = teams is Map ? teams.values : (teams as List? ?? []);
      for (final g in list.whereType<Map>()) {
        if (g['final'] != true) continue;
        if ('${g['team_1_exh']}' == '1' || '${g['team_2_exh']}' == '1') continue;
        final a = '${g['team_1_uuid'] ?? ''}';
        final b = '${g['team_2_uuid'] ?? ''}';
        final sa = int.tryParse('${g['team_score_1']}'.trim());
        final sb = int.tryParse('${g['team_score_2']}'.trim());
        if (a.isEmpty || b.isEmpty || sa == null || sb == null) continue;
        final date = '${g['schedule_time'] ?? ''}'.split(' ').first;
        final game = Game(
          source: source,
          eventId: eventId,
          eventName: eventName,
          date: date,
          division: division,
          teamA: '$source:$a',
          teamB: '$source:$b',
          scoreA: sa,
          scoreB: sb,
        );
        out.add((
          id: '${g['schedule_game_id'] ?? ''}',
          game: game,
          nameA: '${g['team_name_1']}'.trim(),
          nameB: '${g['team_name_2']}'.trim(),
        ));
      }
    }
    return out;
  }
}

class TwoDDivision {
  TwoDDivision({
    required this.eventPriceId,
    required this.scheduleId,
    required this.label,
    required this.urlKey,
  });

  final int eventPriceId;
  final dynamic scheduleId;
  final String label;
  final String urlKey;
}

class TwoDHometown {
  TwoDHometown(this.city, this.state, this.ageClass);
  final String city;
  final String state;
  final String ageClass;
}

class TwoDStandingTeam {
  TwoDStandingTeam(this.uuid, this.name, this.state);
  final String uuid;
  final String name;
  final String state;
}
