# Merging duplicate teams

TeamRank reads games from four tournament orgs: OTC, 2D, Grand Slam (GS) and UACS.
The same real team often appears in more than one org, and sometimes twice in one
org. Each appearance is a **source team**. A merge tells the pipeline that several
source teams are one real team, so the site shows one row with all its games.

Follow these steps in order. Do not skip the checks.

## 1. Source team keys

Every source team has a key. Merges, splits, names, levels and ages all use these keys.

| Org | Key | Where it lives |
|---|---|---|
| OTC | `otc:7100` | `data/otc.json` → `teams` |
| 2D | `2d:d26cbda7-bc68-4364-ab51-4a88725250c9` | `data/2d.json` → `teams` |
| Grand Slam | `gs:31462` | `data/gs.json` → `teams` |
| UACS | `uacs:cba-red\|11` (name + age, no ID on the site) | `data/uacs.json` → `teams` |

In `app/web/data/rankings.json`, a team's `id` is one of its source keys, and its
`sources` list shows every source key in the group. Always copy keys from these
files; never type them from memory.

## 2. Find the teams

Search every source by part of the name (lowercase). Run from the repo root:

```sh
python3 -I - <<'EOF'
import json
q = 'patriots'   # part of the team name, lowercase
for src in ['otc', '2d', 'gs', 'uacs']:
    for k, t in json.load(open(f'data/{src}.json'))['teams'].items():
        if q in t['name'].lower():
            print(k, '|', t['name'], '|', t.get('city'), t.get('state'), '|', t.get('ageClass'))
r = json.load(open('app/web/data/rankings.json'))
for t in r['teams']:
    if q in t['name'].lower():
        print('SITE', t['id'], t['name'], t['age'], 'rank', t['rank'], t['level'], t['levelRank'],
              f"{t['wins']}-{t['losses']}-{t['ties']}", [s['key'] for s in t['sources']])
EOF
```

Search for a short, distinctive word (`patriots`, `havoc`, `cyclone`), not the full
name. Orgs spell names differently ("NOLA" vs "New Orleans", "LA" vs "Louisiana",
"11u" in the name or not, a coach's name after a dash).

## 3. Decide whether they are the same team

Merge only when the person (Jared) or the team's coach says they are one team, or
the evidence is strong and you tell Jared what you merged. Strong evidence means
all of these hold:

- **Same age.** Compare `ageClass`. Grand Slam labels teams by their oldest player
  ("13 & Under"), so a GS listing one year older than the OTC/2D listing can still
  be the same team. Any other age difference means different teams, unless Jared says so.
- **Same club and same coach.** Many clubs field several teams at one age, told apart
  by a coach's name ("LA Havoc - Clemons" vs "LA Havoc - Oster") or a color
  ("Renegades White" vs "Renegades Black"). Different coach or color = different team.
- **Nearby hometown.** Orgs record hometowns by hand. Nearby towns are fine
  (Madisonville and Covington; Gramercy and Lutcher). Far apart = different teams.
  UACS has no hometowns at all.
- **They never played each other or in the same event at the same time.** One team
  cannot be in two dugouts. Check with the script in step 5 before you commit.

If any of these is unclear, ask Jared and list the source keys, names, hometowns,
ages and records of both. Do not guess.

Known decisions (do not redo): Hammond Yankees (OTC 12U) and Hammond Yankees -
Hills/Ogden (2D 11U) are separate. OTC's 13U LA Havoc - Clemons (`otc:6995`) stays
separate from the 11U LA Havoc. Grand Slam softball teams are excluded, never merged.

## 4. Edit `data/aliases.json`

Add one list per real team to `merge`. Put every source key of that team in it:

```json
"merge": [
  ...,
  ["otc:7100", "2d:d26cbda7-bc68-4364-ab51-4a88725250c9"]
]
```

Other sections of the same file:

| Section | Use it to | Example |
|---|---|---|
| `merge` | Join source teams into one team | `["otc:7100", "2d:..."]` |
| `split` | Undo a wrong **automatic** merge | `["otc:7069", "2d:..."]` |
| `names` | Set the name the site shows | `"otc:7003": "Marucci Legacy NOLA 12u"` |
| `levels` | Force a class list: `AA`, `AAA` or `Majors` | `"otc:7023": "AA"` |
| `ages` | Force the age group | `"otc:7158": 12` |
| `exclude` | Drop a team and all its games (wrong sport, not a real team) | `"gs:12345"` |

Keep the JSON valid (commas between entries, no trailing comma). Edit with a script
(`json.load` / `json.dump(..., indent=2)`) if unsure.

**Class after a merge.** A merged team goes on its highest class list:
Majors > AAA > AA (single A counts as AA). So OTC AAA + 2D AA lands in AAA with no
extra setting. Only add a `levels` entry when Jared wants a different list than
that rule gives. A `levels` entry also changes how much a win against the team
counts for its opponents (AA 1, AAA 3, Majors 4), so tell Jared if it moves a team down.

## 5. Check locally before pushing

From `pipeline/` (Flutter's Dart is at `/opt/flutter/bin`):

```sh
export PATH=/opt/flutter/bin:$PATH
dart pub get
git show HEAD:../app/web/data/rankings.json > /tmp/before.json
dart run bin/teamrank.dart rank
```

Then check, using the step 2 script on the new `app/web/data/rankings.json`:

- The old separate rows are gone and one row remains, with `sources` listing every key.
- Its record equals the sum of the old records. If it is **lower**, the two teams
  played each other: games inside one merged team are silently dropped. That means
  they are different teams; remove the merge.
- The class and age are what you expect.
- Compare #1 teams per age and class with `/tmp/before.json` and mention any change to Jared.

Then **throw away the generated files**; the deploy run rebuilds them (your local
build lacks the admin console links):

```sh
cd .. && git checkout -- app/web/data/rankings.json data/review.md
git status --short   # only data/aliases.json should be changed
```

## 6. Commit, push, confirm

- Commit only `data/aliases.json`, directly on `main` (no other branches). Say in the
  message who confirmed the merge (for example "Jared confirmed"). Never name a
  coach or a player in a commit.
- `git push origin main`. Pushing a change to `data/aliases.json` starts the
  "Update rankings" workflow, which ranks (no scraping), commits the data, and deploys.
  It takes about 2 minutes.
- When the run succeeds, read `https://teamrank-la.web.app/data/rankings.json` and
  confirm the merged team shows correctly. Then tell Jared the team's new record and rank.

## Finding duplicates

The pipeline writes `data/review.md` on every run. Read the committed copy on
`main` (the deploy run's version). Its sections:

1. **Merged automatically.** Same normalized name and same hometown, never in the
   same event. Usually right. If one is wrong, add a `split` entry.
2. **Not merged: same name and hometown.** They shared an event, or their names
   give different ages. Usually different squads of one club; leave them unless Jared says otherwise.
3. **Possible duplicates: same name, different hometown.** The best place to look.
   Pontchartrain Patriots (Madisonville vs Covington) was here.
4. **Possible duplicates: similar name, same hometown.** One name contains all the
   words of the other ("LA Bulls - Howell" / "LA Bulls Black 12U - Howell"). Many
   are different squads of one club; check coach names and ages.

Other ways duplicates show up:

- **Two rows on one age list with nearly the same name.** Open the site's All tab
  for each age and scan for repeats, or group `rankings.json` teams by age and a
  shortened name.
- **A team's record is smaller than the coach says.** A coach reporting "we're 10-2"
  when the site shows two rows that add up to 10-2 means those rows are one team.
- **UACS teams** have no hometown. They auto-merge only when exactly one team
  elsewhere has the same normalized name and age; otherwise they stay separate and need a manual merge.
- **A team listed in both AA and AAA** (or two ages) usually means two listings of
  one team, which the merge fixes.

Name matching ignores case, punctuation, "12U"-style age labels and the words
baseball, bb, club, travel, the and team (`normalizeTeamName` in
`pipeline/lib/src/identity.dart`). So "Slidell Raptors 12U" and "Slidell Raptors"
match, but "NOLA" and "New Orleans" do not.

## Where the logic lives

- `pipeline/lib/src/identity.dart`: alias format, `normalizeTeamName`, automatic matching (`groupTeams`).
- `pipeline/lib/src/build.dart`: class (`levelFor`), age, game de-duplication, `review.md`.
- An admin console at `https://teamrank-la.web.app/admin` can also link teams and move
  classes (saved in Firestore, applied on the next run). Prefer `data/aliases.json`,
  which is reviewed in git.
