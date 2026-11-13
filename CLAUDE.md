# TeamRank: notes for AI agents

TeamRank ranks Louisiana 10U-14U travel baseball teams from tournament results
(OTC, 2D, Grand Slam, UACS). Site: https://teamrank-la.web.app.

- `pipeline/`: Dart scraper and ranking (`dart run bin/teamrank.dart scrape|rank|all`).
  Use `export PATH=/opt/flutter/bin:$PATH`. Tests: `dart test` in `pipeline/`.
- `data/`: saved games per org, plus `aliases.json` (manual merges, splits, names,
  classes, ages, excludes) and `review.md` (suggested duplicates).
- `app/`: Flutter web site; reads `app/web/data/rankings.json`.
- `.github/workflows/update.yml`: scrapes, ranks, commits data and deploys. A push to
  `main` that touches `app/`, `pipeline/`, `data/aliases.json` or `firebase.json` re-ranks and deploys.

Rules:

- Commit and push directly to `main`. Do not create other branches.
- Never commit secrets. The deploy is keyless.
- Don't commit a locally built `app/web/data/rankings.json` or `data/review.md`;
  the workflow rebuilds them.

**Merging duplicate teams, finding duplicates, or changing a team's class or age:
read [docs/merging-teams.md](docs/merging-teams.md) first and follow it step by step.**
