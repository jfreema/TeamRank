import 'dart:convert';

import 'package:http/http.dart' as http;

import 'identity.dart';

/// Team links saved in the admin console, stored in Firestore's `links`
/// collection. Each document has a `type` (`merge`, `split`, `name`, `level`
/// or `age`), the team `keys` it applies to, and for `name`, `level` and
/// `age` a `value`.
Future<Aliases> fetchAdminLinks({
  required String projectId,
  required String accessToken,
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  final docs = <Map<String, dynamic>>[];
  String? pageToken;
  try {
    do {
      final url = Uri.https('firestore.googleapis.com',
          '/v1/projects/$projectId/databases/(default)/documents/links', {
        'pageSize': '300',
        if (pageToken != null) 'pageToken': pageToken,
      });
      final res = await c.get(url, headers: {'Authorization': 'Bearer $accessToken'});
      if (res.statusCode != 200) {
        throw Exception('Firestore links: ${res.statusCode} ${res.body}');
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      docs.addAll((body['documents'] as List? ?? []).cast<Map<String, dynamic>>());
      pageToken = body['nextPageToken'] as String?;
    } while (pageToken != null);
  } finally {
    if (client == null) c.close();
  }
  return linksToAliases(docs.map((d) => d['fields'] as Map<String, dynamic>? ?? {}));
}

/// Converts Firestore REST documents' `fields` into [Aliases].
Aliases linksToAliases(Iterable<Map<String, dynamic>> fields) {
  final merge = <List<String>>[];
  final split = <List<String>>[];
  final names = <String, String>{};
  final levels = <String, String>{};
  final ages = <String, int>{};
  for (final f in fields) {
    final type = f['type']?['stringValue'] as String?;
    final keys = [
      for (final v in (f['keys']?['arrayValue']?['values'] as List? ?? []))
        if (v['stringValue'] case final String s) s
    ];
    final value = f['value']?['stringValue'] as String? ?? '';
    if (keys.isEmpty) continue;
    switch (type) {
      case 'merge' when keys.length > 1:
        merge.add(keys);
      case 'split' when keys.length > 1:
        split.add(keys);
      case 'name' when value.isNotEmpty:
        for (final k in keys) {
          names[k] = value;
        }
      case 'level' when value == 'AA' || value == 'AAA' || value == 'Majors':
        for (final k in keys) {
          levels[k] = value;
        }
      case 'age' when int.tryParse(value) != null:
        for (final k in keys) {
          ages[k] = int.parse(value);
        }
    }
  }
  return Aliases(merge: merge, split: split, names: names, levels: levels, ages: ages);
}
