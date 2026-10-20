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
}
