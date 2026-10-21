import 'package:teamrank_pipeline/teamrank_pipeline.dart';
import 'package:test/test.dart';

String row(String n, String date, String home, String hs, String away, String as) => '''
<tr>
 <td><span id="g_ctl0${n}_DateLabel">$date</span></td>
 <td><span id="g_ctl0${n}_TimeLabel">9:00 AM</span></td>
 <td>
  <span id="g_ctl0${n}_HomeLabel">$home</span>&nbsp;<span id="g_ctl0${n}_HomeScoreLabel">$hs</span><br />
  <span id="g_ctl0${n}_AwayLabel">$away</span>&nbsp;<span id="g_ctl0${n}_AwayScoreLabel">$as</span><br />
  <a id="g_ctl0${n}_LocationLink" href="http://maps.google.com/maps?li=rwp&amp;q=13505%20LA-%201085%2CCovington%2CLA%2070433"><span id="g_ctl0${n}_LocationLabel">CPC/F-$n</span></a>
 </td>
</tr>''';

String page(String rows, String playoff) => '''
<div id="TitlePanel"><h1> October 24-25 Halloween HAVOC </h1><div id="PageSubTitleSpan" class="subHdr"> 12u- Open </div></div>
<table id="x_ScheduleGrid"><tr><td>desktop copy ignored</td></tr></table>
<div id="ctl00_ContentPlaceHolder1_StandingsResultsControl_MobileScheduleGrid"><table>$rows</table></div>
<div id="ctl00_ContentPlaceHolder1_StandingsResultsControl_MobilePlayoffGrid"><table>$playoff</table></div>
''';

void main() {
  final season = Season.containing(DateTime(2026, 10, 20));

  test('reads finished pool and playoff games, skipping unplayed ones', () {
    final body = page(
      row('1', 'Sat 10/24', 'Saints-12u', '7', 'MYB Green 12u', '3') +
          row('2', 'Sat 10/24', 'SBG Sox-Dartez', '', 'Saints-12u', ''),
      row('3', 'Sun 10/25', 'MYB Green 12u', '5', 'Saints-12u', '6'),
    );
    final d = UacsScraper.parseDivision(body, '728425', season)!;
    expect(d.event, 'October 24-25 Halloween HAVOC');
    expect(d.division, '12u- Open');
    expect(d.games, hasLength(2));
    final g = d.games.first;
    expect(g.date, '2026-10-24');
    expect(g.teamA, 'uacs:saints|12');
    expect((g.scoreA, g.scoreB), (7, 3));
    expect(d.games.last.date, '2026-10-25');
    final saints = d.teams.firstWhere((t) => t.key == 'uacs:saints|12');
    expect(saints.state, 'LA', reason: 'from the fields it played on');
    expect(saints.name, 'Saints-12u');
  });

  test('a switched-off division gives nothing', () {
    const body = '<div id="TitlePanel"><h1>Aug 29-30 UACS Fall Kick-Off</h1></div>'
        'The League Administrator has de-activated the Standings &amp; Schedule for the Division';
    expect(UacsScraper.parseDivision(body, '728000', season), isNull);
  });

  test('schedule links are read once each', () {
    const body = '<a href="/sites/UACSSports/schedule/728425/12u-Open">12u- Open</a>'
        '<a href="/schedule/728425/12u-open">again</a><a href="/schedule/728426/13u-AA">13u</a>';
    expect(UacsScraper.parseScheduleLinks(body).map((d) => d.id), ['728425', '728426']);
  });

  test('UACS teams match the one team elsewhere with that name and age', () {
    final teams = [
      SourceTeam(key: '2d:1', name: 'Saints', city: 'Prairieville', state: 'LA', ageClass: '12u AA'),
      SourceTeam(key: 'uacs:saints|12', name: 'Saints-12u', state: 'LA', ageClass: '12u- Open'),
      SourceTeam(key: 'otc:1', name: 'MYB Green', city: 'Mandeville', state: 'LA', ageClass: '12U-AA'),
      SourceTeam(key: '2d:2', name: 'MYB Green', city: 'Madisonville', state: 'LA', ageClass: '12u AA'),
      SourceTeam(key: 'uacs:myb-green|12', name: 'MYB Green 12u', state: 'LA', ageClass: '12u- Open'),
      SourceTeam(key: 'otc:2', name: 'River Bandits', city: 'Houma', state: 'LA', ageClass: '11U-AA'),
      SourceTeam(key: 'uacs:river-bandits|12', name: '12U River Bandits', state: 'LA', ageClass: '12u- Open'),
    ];
    final g = groupTeams(teams, Aliases()).groupOf;
    expect(g['uacs:saints|12'], g['2d:1']);
    expect(g['uacs:myb-green|12'], 'uacs:myb-green|12', reason: 'two teams fit, so it is left alone');
    expect(g['uacs:river-bandits|12'], 'uacs:river-bandits|12', reason: 'a different age');
  });
}
