import 'dart:convert';
import 'dart:io';

import 'package:teamrank_pipeline/teamrank_pipeline.dart';

const usage = '''
Usage: dart run bin/teamrank.dart [scrape|rank|all] [--source otc|2d] [--data DIR] [--out FILE]

  scrape   Fetch new and in-progress events into DIR/<source>.json
  rank     Build the rankings file from what has been scraped
  all      scrape, then rank (default)
''';

const firebaseProject = 'teamrank-la';

Future<void> main(List<String> args) async {
  var command = 'all';
  var dataDir = '../data';
  var out = '../app/web/data/rankings.json';
  final sources = <String>{};
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case 'scrape' || 'rank' || 'all':
        command = args[i];
      case '--source':
        sources.add(args[++i]);
      case '--data':
        dataDir = args[++i];
      case '--out':
        out = args[++i];
      default:
        stderr.write(usage);
        exit(64);
    }
  }
  if (sources.isEmpty) sources.addAll(['otc', '2d']);

  final today = DateTime.now();
  final season = Season.containing(today);

  if (command != 'rank') {
    final client = PoliteClient();
    var failed = false;
    for (final s in sources) {
      final cache = loadCache(dataDir, s, season.label);
      try {
        if (s == 'otc') {
          await OtcScraper(client).scrape(cache, season, today);
        } else if (s == '2d') {
          await TwoDScraper(client).scrape(cache, season, today);
        }
      } catch (e) {
        // Keep what the other source found; a site being down for a night
        // should not wipe out the rankings.
        stderr.writeln('$s: scrape failed: $e');
        failed = true;
      }
      saveJson('$dataDir/$s.json', cache.toJson());
      print('$s: ${cache.events.length} events, ${cache.games.length} games, '
          '${cache.teams.length} teams');
    }
    print('${client.requestCount} requests');
    client.close();
    if (failed && command == 'scrape') exitCode = 1;
  }

  if (command != 'scrape') {
    final caches = [for (final s in ['otc', '2d']) loadCache(dataDir, s, season.label)];
    final aliasFile = File('$dataDir/aliases.json');
    var aliases = aliasFile.existsSync()
        ? Aliases.fromJson(jsonDecode(aliasFile.readAsStringSync()) as Map<String, dynamic>)
        : Aliases();
    // Links saved in the admin console. The nightly workflow provides a
    // short-lived token; without one, only data/aliases.json is used.
    final token = Platform.environment['FIRESTORE_ACCESS_TOKEN'] ?? '';
    if (token.isNotEmpty) {
      try {
        final links = await fetchAdminLinks(projectId: firebaseProject, accessToken: token);
        print('admin links: ${links.merge.length} merges, ${links.split.length} splits, '
            '${links.names.length} names, ${links.levels.length} levels');
        aliases = aliases.combine(links);
      } catch (e) {
        stderr.writeln('admin links not loaded: $e');
      }
    }
    final (:rankings, :review) = buildRankings(
      caches: caches,
      aliases: aliases,
      season: season.label,
      generatedAt: DateTime.now(),
    );
    saveJson(out, rankings);
    File('$dataDir/review.md').writeAsStringSync(review);
    final ranked = (rankings['teams'] as List).where((t) => t['rank'] != null).length;
    print('rankings: $ranked Louisiana teams ranked, '
        '${(rankings['games'] as List).length} games -> $out');
  }
}

SourceCache loadCache(String dir, String source, String season) {
  final f = File('$dir/$source.json');
  if (f.existsSync()) {
    final c = SourceCache.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
    if (c.season == season) return c;
  }
  // A new season starts from scratch.
  return SourceCache(source: source, season: season);
}

void saveJson(String path, Object json) {
  final f = File(path)..parent.createSync(recursive: true);
  f.writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(json)}\n');
}
