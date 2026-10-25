import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teamrank_pipeline/teamrank_pipeline.dart';
import 'package:test/test.dart';

const details = '''
<hgroup>
  <h3 class="inline-block block-xs block-sm m0"> Monroe, LA </h3>
  <h3 class="inline-block block-xs m0"> <span class="hidden-xs">|</span> Restoration Park </h3>
  <h1 class="mv-sm"> <strong>Fall Classic</strong> </h1>
  <h3 class="inline-block m0"> Oct 10-11 </h3>
</hgroup>
<a href="/baseball/Events/Schedule/4600/fall-classic?division=12U-AA">12U-AA</a>
''';

const teamPage = '''
<div id="team-details"><div class="row row-header">
  <div class="relative">
    <div class="h3 inline-block m0 text-red text-uppercase"> LA - Monroe </div>
    <div class="h1 mv-sm"> <strong> Monroe Mudcats 12U </strong> </div>
    <div class="h4 inline-block m0 text-red"> 12 &amp; Under AA </div>
  </div>
  <div class="team-photo"><img src="https://grandslamtournaments.com/Images/team-silhouette.jpg" /></div>
</div></div>
<table><tbody><tr>
  <td data-title="Start Date">10/10/2026</td>
  <td data-title="Event"><a href="/baseball/Events/Details/4600/fall-classic"> Fall Classic </a></td>
  <td data-title="Division">12U-AA</td>
</tr></tbody></table>
<div id="eventTeam-1" class="tab-pane">
  <div class="h3 page-header text-center">
    <div><small>12U-AA</small></div>
    <div class="pt">Fall Classic</div>
    <div> <small>Oct 10-11</small> <small class="pl">Monroe, LA</small> </div>
  </div>
  <table><tbody>
    <tr><td>1</td><td>10/10 9:00 AM</td><td>Field 1</td>
      <td><a href="/baseball/Teams/Details/100/monroe-mudcats-12u">Monroe Mudcats 12U</a></td>
      <td><span class="text-nowrap"> 6 - 11 </span></td>
      <td class="winner"><a href="/baseball/Teams/Details/200/ruston-rays">Ruston Rays</a></td></tr>
    <tr><td>2</td><td>10/11 9:00 AM</td><td>Field 1</td>
      <td><a href="/baseball/Teams/Details/100/monroe-mudcats-12u">Monroe Mudcats 12U</a></td>
      <td><span class="text-nowrap"> - </span></td>
      <td><a href="/baseball/Teams/Details/300/tbd">TBD</a></td></tr>
  </tbody></table>
</div>
''';

void main() {
  test('reads an event details page', () {
    final e = GrandSlamScraper.parseEventDetails(details, DateTime(2026, 10, 20))!;
    expect(e.name, 'Fall Classic');
    expect(e.state, 'LA');
    expect(e.start, DateTime(2026, 10, 10));
    expect(e.lengthDays, 2);
    expect(OtcScraper.parseDivisions(details), ['12U-AA']);
  });

  test('reads a team page with its games grouped by event', () {
    final p = GrandSlamScraper.parseTeamPage(teamPage, '100');
    expect(p.team.key, 'gs:100');
    expect(p.team.name, 'Monroe Mudcats 12U');
    expect(p.team.city, 'Monroe');
    expect(p.team.state, 'LA');
    expect(ageOf(p.team.ageClass), 12);
    expect(levelOf(p.team.ageClass), 'AA');
    expect(p.team.logo, '', reason: 'silhouette is the placeholder');
    expect(p.events['4600']!.start, DateTime(2026, 10, 10));
    expect(p.events['4600']!.lengthDays, 2);
    expect(p.games, hasLength(1), reason: 'unplayed games have no score');
    expect(p.names['200'], 'Ruston Rays');
    final games = GrandSlamScraper.collectEventGames('4600', 'Fall Classic', [p]);
    expect(games.single.teamB, 'gs:200');
    expect(games.single.scoreB, 11);
    expect(games.single.division, '12U-AA');
  });

  group('a page that fails', () {
    // A Grand Slam site where some pages fail, like a timeout that outlasts
    // the client's retries.
    PoliteClient site(Map<String, String? Function()> pages, List<String> asked) =>
        PoliteClient(delay: Duration.zero, inner: MockClient((req) async {
          final path = '${req.url.path}${req.url.hasQuery ? '?${req.url.query}' : ''}';
          asked.add(path);
          final page = pages[path];
          if (page == null) return http.Response('not found', 404);
          final body = page();
          if (body == null) throw http.ClientException('timed out', req.url);
          return http.Response(body, 200);
        }));
    SourceCache saved() => SourceCache(source: 'gs', season: '2026-27', teams: {}, events: {
          '4600': EventRecord(id: '4600', name: 'Fall Classic', startDate: '2026-10-10', endDate: '2026-10-11',
              isFinal: false, games: [], teamKeys: []),
        });
    final today = DateTime(2026, 10, 20);
    final season = Season.containing(today);

    test('is skipped and tried again next run, without stopping the rest', () async {
      var newEventUp = false;
      final asked = <String>[];
      final client = site({
        '/baseball/Events?page=1': () => '<a href="/baseball/Events/Details/4602/x">x</a>',
        '/baseball/Events/Details/4600': () => details,
        // A new event whose page times out the first time.
        '/baseball/Events/Details/4601': () => newEventUp ? details.replaceAll('Monroe, LA', 'Tyler, TX') : null,
        '/baseball/Events/Schedule/4600/x?division=12U-AA': () =>
            '<a href="/baseball/Teams/Details/100/a">a</a><a href="/baseball/Teams/Details/200/b">b</a>',
        '/baseball/Teams/Details/100/team': () => teamPage,
        '/baseball/Teams/Details/200/team': () => null,
      }, asked);
      final cache = saved();
      await GrandSlamScraper(client).scrape(cache, season, today, log: (_) {});
      expect(cache.events['4601']!.isFinal, isFalse, reason: 'waits to be read again');
      expect(cache.events['4602']!.isFinal, isTrue, reason: 'a page that does not exist is skipped for good');
      expect(cache.events['4600']!.games, hasLength(1), reason: 'the rest of the run went on');

      newEventUp = true;
      asked.clear();
      await GrandSlamScraper(client).scrape(cache, season, today, log: (_) {});
      expect(asked, contains('/baseball/Events/Details/4601'));
      expect(cache.events['4601']!.isFinal, isTrue, reason: 'read this time: a Texas event');
    });

    test('three in a row stop the scrape, keeping what was saved', () async {
      final asked = <String>[];
      final client = site({
        for (final id in [4600, 4601, 4602, 4603]) '/baseball/Events/Details/$id': () => null,
        '/baseball/Events?page=1': () => null,
      }, asked);
      final cache = saved()
        ..events['4601'] = EventRecord(id: '4601', name: 'Gulf Coast', startDate: '2026-10-17', endDate: '2026-10-18',
            isFinal: false, games: [], teamKeys: [])
        ..events['4603'] = EventRecord(id: '4603', name: 'Bayou Bash', startDate: '2026-10-17', endDate: '2026-10-18',
            isFinal: false, games: [], teamKeys: []);
      await expectLater(GrandSlamScraper(client).scrape(cache, season, today, log: (_) {}), throwsStateError);
      expect(asked, hasLength(3));
      expect(cache.events['4601']!.name, 'Gulf Coast', reason: 'saved events are kept');
    });
  });
}
