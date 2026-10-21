# TeamRank

Rankings for Louisiana 10U to 14U travel baseball teams, built from game results at
[OTC Sports](https://offthecrosssports.com/baseball),
[2D Sports](https://youth.2dsports.org),
[Grand Slam](https://grandslamtournaments.com/baseball) and
[UACS](https://www.uacssports.com) events.

## How it works

```
pipeline/   Dart: scrapes results, matches teams, computes rankings
data/       What the scrapers found (committed so each run only fetches new events)
app/        Flutter web app that shows the rankings
```

1. **Scrape.** `pipeline` collects every finished game from 10U to 14U divisions this
   season (August 1 to July 31) at OTC, 2D, Grand Slam and UACS events, with each team's
   hometown. Events that ended more than three days ago are saved to
   `data/otc.json`, `data/2d.json`, `data/gs.json` and `data/uacs.json` and never fetched again. Requests are
   sent one at a time with a pause between them.
   Grand Slam runs nationwide and lists only upcoming events, so its scraper
   walks event IDs (they count up) and keeps Louisiana events plus the games
   Louisiana teams played at Grand Slam events in other states. Grand Slam's
   fast pitch softball events and teams are left out.
   UACS (TeamSideline) only shows a tournament's scores while its divisions
   are active, so each run saves the divisions on its schedules page (UACS
   results start with Halloween Havoc, Oct 24-25, 2026). UACS gives no team
   IDs or hometowns: a team is matched by name to the one team elsewhere with
   that name and age, and otherwise takes the state of the fields it played on.
2. **Remove duplicates.**
   - Games: a game listed on both teams' pages, or in two divisions'
     schedules (crossover games), is counted once. Games that two orgs both
     report (same date, same teams, same score) are also counted once.
   - Teams: the same team listed by both orgs, or registered twice with one
     org, is merged into one entry when the names and hometowns match and the
     two listings never played in the same event. Anything uncertain is left
     alone and listed in `data/review.md`.
3. **Rank.** Ratings use the [Colley Matrix](https://en.wikipedia.org/wiki/Colley_Matrix)
   method. Every team's rating depends on who it beat and who those teams
   beat, so beating a strong team counts for a lot and beating a winless team
   barely counts. Run differential counts too (`winShare` in
   `pipeline/lib/src/colley.dart`): a one-run win is 0.64 of a win (the loser keeps 0.36), rising
   to a full win at 10+ runs, with the loser keeping the rest. Out-of-state opponents count
   toward ratings, but only Louisiana teams are ranked.
   AA teams (including A), AAA teams and Majors teams get separate lists, based on
   the class each team registered in. Everyone is still rated in one pool,
   so games between levels count. Set a team's list with `levels` in
   `data/aliases.json` if its class is wrong or missing. A win over a
   AAA team counts as 3 games and over a Majors team as 4, and a loss to
   a AAA team costs a third of a normal loss, to a Majors team a quarter
   (`aaaWinWeight`, `majorsWinWeight`, `aaaLossScale`, `majorsLossScale` in
   `pipeline/lib/src/build.dart`).
   Direct matchups count extra (`headToHeadAdjusted` in
   `pipeline/lib/src/colley.dart`): when a team beat a higher-rated team
   (more wins than losses against it), each moves by 60% of the gap, at most
   0.06, so a winner within 0.10 passes the team it beat.
   Each team is listed at the age it registered as (10U to 14U), even when
   it plays up, and ranked within that age. All ages share one rating pool,
   so games across ages count. Set a team's age with `ages` in
   `data/aliases.json` if needed (`minAge` and `maxAge` in
   `pipeline/lib/src/identity.dart` set the covered ages; after changing
   them, run `dart run bin/teamrank.dart scrape --refetch` once so events
   already saved are read again for the new ages).
4. **Publish.** The result is `app/web/data/rankings.json`, which the app
   loads when it opens.

A GitHub Action (`.github/workflows/update.yml`) runs all of this every
night, commits the new data, builds the site and deploys it to Firebase
Hosting.

## Fixing team matches

The easiest way is the admin console at <https://teamrank-la.web.app/admin>.
Sign in with Google (accounts listed in Firestore's `admins` collection) to
link listings of the same team, split wrong matches, move a team between
the AA, AAA and Majors lists, or rename it. Changes are saved to the
Firestore `links` collection (free tier) and applied at the next scheduled
update.

You can also edit `data/aliases.json` and push to `main`. The site
redeploys without re-scraping.

```json
{
  "merge": [["otc:7158", "2d:fc31e3be-7d40-4a36-a33a-9953e5697dbd"]],
  "split": [["otc:7069", "2d:60f64dd6-053c-4598-a639-047bc69816cd"]],
  "names": {"otc:7158": "Slidell Raptors"},
  "levels": {"otc:7158": "AAA"},
  "ages": {"otc:7158": 12},
  "exclude": []
}
```

- `merge`: these listings are the same team.
- `split`: these listings were merged automatically but are different teams.
- `names`: the display name to use.
- `levels`: put a team in the `AA`, `AAA` or `Majors` list.
- `ages`: the age group to list a team in.
- `exclude`: drop a listing and its games.

Team keys are `otc:<id>` (from the OTC team page URL) or `2d:<uuid>` (from
the 2D team page URL). `data/review.md` lists automatic merges and likely
duplicates after each run.

## Hosting

The site is live at <https://teamrank-la.web.app> (Firebase project
`teamrank-la`, free Spark plan).

The update workflow (Sat, Sun, Mon and Wed at 10 PM Central) deploys with Workload Identity Federation: GitHub's
OIDC token is exchanged for short-lived credentials of the
`github-deploy@teamrank-la.iam.gserviceaccount.com` service account, which
only has the Firebase Hosting Admin and Service Usage Consumer roles and only accepts tokens from
`jfreema/TeamRank`. No keys or GitHub secrets are involved.

To deploy by hand: `firebase deploy --only hosting` after
`cd app && flutter build web --release`.

## Running locally

```sh
cd pipeline
dart pub get
dart run bin/teamrank.dart all     # scrape + rank (or: scrape, rank)
dart test

cd ../app
flutter run -d chrome
flutter test
```
