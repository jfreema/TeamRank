# TeamRank

Rankings for Louisiana 12U travel baseball teams, built from game results at
[OTC Sports](https://offthecrosssports.com/baseball) and
[2D Sports](https://youth.2dsports.org) events.

## How it works

```
pipeline/   Dart: scrapes results, matches teams, computes rankings
data/       What the scrapers found (committed so each run only fetches new events)
app/        Flutter web app that shows the rankings
```

1. **Scrape.** `pipeline` collects every finished game from 12U divisions this
   season (August 1 to July 31) at OTC and 2D events, with each team's
   hometown. Events that ended more than three days ago are saved to
   `data/otc.json` and `data/2d.json` and never fetched again. Requests are
   sent one at a time with a pause between them.
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
   barely counts. Margin of victory is ignored. Out-of-state opponents count
   toward ratings, but only Louisiana teams are ranked.
4. **Publish.** The result is `app/web/data/rankings.json`, which the app
   loads when it opens.

A GitHub Action (`.github/workflows/update.yml`) runs all of this every
night, commits the new data, builds the site and deploys it to Firebase
Hosting.

## Fixing team matches

Edit `data/aliases.json` and push to `main`. The site redeploys without
re-scraping.

```json
{
  "merge": [["otc:7158", "2d:fc31e3be-7d40-4a36-a33a-9953e5697dbd"]],
  "split": [["otc:7069", "2d:60f64dd6-053c-4598-a639-047bc69816cd"]],
  "names": {"otc:7158": "Slidell Raptors"},
  "exclude": []
}
```

- `merge`: these listings are the same team.
- `split`: these listings were merged automatically but are different teams.
- `names`: the display name to use.
- `exclude`: drop a listing and its games.

Team keys are `otc:<id>` (from the OTC team page URL) or `2d:<uuid>` (from
the 2D team page URL). `data/review.md` lists automatic merges and likely
duplicates after each run.

## Hosting

The site is live at <https://teamrank-la.web.app> (Firebase project
`teamrank-la`, free Spark plan).

The nightly workflow deploys with Workload Identity Federation: GitHub's
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
