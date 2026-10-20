import 'package:teamrank_pipeline/teamrank_pipeline.dart';
import 'package:test/test.dart';

/// Trimmed-down copies of the markup each site uses.
const otcListing = '''
<div class="media">
  <div class="media-body">
    <div class="h6 m0 hidden-xs"><span>Hammond, LA</span></div>
    <div class="h4"><a href="/Baseball/Events/Details/1141/gulf-coast-fall-state">Gulf Coast Fall State</a></div>
    <div class="h4">Oct 10-11</div>
    <div class="h6">9U &middot; 10U &middot; 12U &middot; 14U-60/90</div>
  </div>
</div>
<div class="media">
  <div class="media-body">
    <div class="h4"><a href="/Baseball/Events/Details/996/spring-fling">Spring Fling</a></div>
    <div class="h4">May 10-11, 2025</div>
    <div class="h6">8U &middot; 9U</div>
  </div>
</div>
''';

const otcTeam = '''
<div id="team-details"><div class="row row-header"><div><div class="relative">
  <div class="h3 inline-block m0 text-red text-uppercase">Slidell, LA</div>
  <div class="h1 mv-sm"><strong>Slidell Raptors</strong></div>
  <div class="h4 inline-block m0 text-red">12U-AA</div>
</div></div></div></div>
<table><tbody>
  <tr>
    <td data-title="Place"><span>6</span></td>
    <td data-title="Start Date">10/10/2026</td>
    <td data-title="Event"><a href="/Baseball/Events/Details/1141/gulf-coast">Gulf Coast</a></td>
    <td data-title="Division">12U-AA</td>
  </tr>
  <tr>
    <td data-title="Start Date">9/5/2026</td>
    <td data-title="Event"><a href="/Baseball/Events/Details/1130/play-up">Play Up</a></td>
    <td data-title="Division">13U-OPEN</td>
  </tr>
</tbody></table>
<table><tbody>
  <tr>
    <td><span>4</span></td>
    <td><a href="/Baseball/Events/Details/1141/gulf-coast">Gulf Coast</a></td>
    <td class="winner"><span class="visible-xs">12</span><a href="/Baseball/Teams/Details/7158/slidell-raptors">Slidell Raptors</a></td>
    <td><span class="text-nowrap">12 - 3</span></td>
    <td><span class="visible-xs">3</span><a href="/Baseball/Teams/Details/7252/walker-elite">Walker Elite</a></td>
  </tr>
  <tr>
    <td><span>5</span></td>
    <td><a href="/Baseball/Events/Details/1130/play-up">Play Up</a></td>
    <td><a href="/Baseball/Teams/Details/7158/slidell-raptors">Slidell Raptors</a></td>
    <td><span class="text-nowrap">2 - 9</span></td>
    <td><a href="/Baseball/Teams/Details/8000/big-kids">Big Kids</a></td>
  </tr>
  <tr>
    <td><span>6</span></td>
    <td><a href="/Baseball/Events/Details/1171/king-of-the-bayou">King of the Bayou</a></td>
    <td><a href="/Baseball/Teams/Details/7158/slidell-raptors">Slidell Raptors</a></td>
    <td><span class="text-nowrap">vs</span></td>
    <td><a href="/Baseball/Teams/Details/7252/walker-elite">Walker Elite</a></td>
  </tr>
</tbody></table>
''';

void main() {
  group('OTC', () {
    final today = DateTime(2026, 10, 20);

    test('reads event listings, dates and 12U divisions', () {
      final l = OtcScraper.parseListings(otcListing, today: today);
      expect(l.map((e) => e.id), ['1141', '996']);
      expect(l[0].start, DateTime(2026, 10, 10));
      expect(l[0].lengthDays, 2);
      expect(l[0].has12U, isTrue);
      expect(l[1].start, DateTime(2025, 5, 10));
      expect(l[1].has12U, isFalse);
    });

    test('team logos skip the placeholder image', () {
      expect(OtcScraper.parseLogo('https://offthecrosssports.com/Images/no-image-available.jpg'), '');
      expect(OtcScraper.parseLogo('https://offthechain.blob.core.windows.net/documents/images/Teams/7096-x.jpeg?v=1'),
          'https://offthechain.blob.core.windows.net/documents/images/Teams/7096-x.jpeg?v=1');
      expect(
          TwoDScraper.parseTeamLogo(
              '<div class="team-logo-content"><img src="https://youth.2dsports.org/frontend/themes/2dsports/images/logos/logo.png"></div>'),
          '');
      expect(
          TwoDScraper.parseTeamLogo(
              '<div class="team-logo-content"><img src="https://nyc3.digitaloceanspaces.com/m1.pb365/x/files/images/teams/t.png"></div>'),
          'https://nyc3.digitaloceanspaces.com/m1.pb365/x/files/images/teams/t.png');
    });

    test('dates without a year pick the nearest past year', () {
      final (start, len) = OtcScraper.parseListingDate('Dec 30-Jan 1', DateTime(2027, 1, 5));
      expect(start, DateTime(2026, 12, 30));
      expect(len, 3);
    });

    test('reads a team page: hometown, events and finished games', () {
      final p = OtcScraper.parseTeamPage(otcTeam, '7158');
      expect(p.team.name, 'Slidell Raptors');
      expect(p.team.city, 'Slidell');
      expect(p.team.state, 'LA');
      expect(p.events['1141']!.division, '12U-AA');
      expect(p.games, hasLength(2), reason: 'the unplayed game has no score');
      expect(p.games.first.scoreA, 12);
      expect(p.games.first.teamB, '7252');
    });

    test('collects each game once from both teams\' pages, 12U only', () {
      final raptors = OtcScraper.parseTeamPage(otcTeam, '7158');
      final elite = OtcTeamPage(
        SourceTeam(key: 'otc:7252', name: 'Walker Elite'),
        {'1141': OtcTeamEvent(DateTime(2026, 10, 10), '12U-AA')},
        [
          OtcTeamGame(eventId: '1141', teamA: '7158', teamB: '7252', scoreA: 12, scoreB: 3),
        ],
      );
      final listing = OtcScraper.parseListings(otcListing, today: today).first;
      final games = OtcScraper.collectEventGames(listing, [raptors, elite]);
      expect(games, hasLength(1));
      expect(games.single.date, '2026-10-10');

      final playUp = OtcListing(
          id: '1130', slug: 'play-up', name: 'Play Up', start: null, lengthDays: 2, has12U: true);
      expect(OtcScraper.collectEventGames(playUp, [raptors]), isEmpty,
          reason: 'a 13U division game is not a 12U result');
    });
  });

  group('2D', () {
    test('reads the divisions object embedded in a page', () {
      const page = '''<script>
        window.BASE_URL = "x";
        window.DIVISIONS = {"43964":{"event_price_id":43964,"label":"12u AA ","url_key":"12u-aa-","schedule_id":27469,"note":"a } in a string"},
                            "43965":{"event_price_id":43965,"label":"11u AA ","url_key":"11u-aa-","schedule_id":27470}};
        window.EVENT_ID = "1866";
      </script>''';
      final d = TwoDScraper.parseDivisions(page);
      expect(d, hasLength(2));
      expect(d.where((x) => TwoDScraper.is12U(x.label)).single.scheduleId, 27469);
    });

    test('finds division links on the schedule page', () {
      const page = '''
        <a href="https://youth.2dsports.org/events/hit-fest-la-10-17-2026/teams">Teams</a>
        <a href="https://youth.2dsports.org/events/hit-fest-la-10-17-2026/12u-aa-">12u AA</a>
        <a href="https://youth.2dsports.org/events/hit-fest-la-10-17-2026/12u-open-">12u Open</a>
        <a href="https://youth.2dsports.org/events/hit-fest-la-10-17-2026/10u-aa-">10u AA</a>
        <a href="https://youth.2dsports.org/events/hit-fest-la-10-17-2026/schedule/all">All</a>''';
      expect(TwoDScraper.parseDivisionLinks(page, 'hit-fest-la-10-17-2026').where(TwoDScraper.is12U),
          ['12u-aa-', '12u-open-']);
    });

    test('reads team hometowns from the teams page', () {
      const page = '''
        <div><span><span><a href="https://youth.2dsports.org/team/details/2026-27-season/fc31e3be-7d40-4a36-a33a-9953e5697dbd">Louisiana Shockers</a></span>
        <small> Hammond,
           LA  | (12u
             AA )</small></span></div>''';
      final h = TwoDScraper.parseTeamHometowns(page);
      final t = h['fc31e3be-7d40-4a36-a33a-9953e5697dbd']!;
      expect(t.city, 'Hammond');
      expect(t.state, 'LA');
      expect(t.ageClass, '12u AA');
    });

    test('keeps final games only and skips exhibitions', () {
      final feed = {
        'schedules': {
          '1': {
            'teams': [
              _g(1, 'a', 'b', '08', '07'),
              _g(2, 'a', 'c', '', '', isFinal: false),
              _g(3, 'b', 'c', '5', '1', exh: 1),
            ]
          },
          '2': {
            'teams': {'0': _g(4, 'c', 'a', '11', '00')}
          },
        }
      };
      final games = TwoDScraper.parseScheduleGames(feed,
          eventId: '1866', eventName: 'Hit Fest', division: '12u AA');
      expect(games.map((g) => g.id), ['1', '4']);
      expect(games.first.game.scoreA, 8);
      expect(games.first.game.teamA, '2d:a');
      expect(games.last.game.date, '2026-10-18');
    });
  });

  test('seasons run August through July', () {
    expect(Season.containing(DateTime(2026, 10, 20)).label, '2026-27');
    expect(Season.containing(DateTime(2027, 5, 1)).label, '2026-27');
    expect(Season.containing(DateTime(2026, 7, 31)).label, '2025-26');
  });
}

Map<String, dynamic> _g(int id, String a, String b, String sa, String sb,
        {bool isFinal = true, int exh = 0}) =>
    {
      'schedule_game_id': id,
      'team_1_uuid': a,
      'team_2_uuid': b,
      'team_name_1': a.toUpperCase(),
      'team_name_2': b.toUpperCase(),
      'team_score_1': sa,
      'team_score_2': sb,
      'team_1_exh': exh,
      'team_2_exh': 0,
      'final': isFinal,
      'schedule_time': id == 4 ? '2026-10-18 09:00:00' : '2026-10-17 09:00:00',
    };
