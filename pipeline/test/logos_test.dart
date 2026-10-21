import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:teamrank_pipeline/teamrank_pipeline.dart';
import 'package:test/test.dart';

void main() {
  test('logos are copied to the site, shrunk, and old copies removed', () async {
    final web = Directory.systemTemp.createTempSync('logos');
    addTearDown(() => web.deleteSync(recursive: true));
    final big = img.encodePng(img.Image(width: 600, height: 300, numChannels: 4));
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return req.url.path.contains('broken') ? http.Response('nope', 404) : http.Response.bytes(big, 200);
    });
    Directory('${web.path}/logos').createSync();
    File('${web.path}/logos/stale.jpg').writeAsStringSync('old');
    Map<String, dynamic> rankings() => {
          'teams': [
            {'id': 'a', 'logo': 'https://cdn.example/a.png'},
            {'id': 'b', 'logo': 'https://cdn.example/broken.png'},
            {'id': 'c', 'logo': null},
            // Hashes to a negative 64-bit number.
            {'id': 'd', 'logo': 'https://offthechain.blob.core.windows.net/documents/images/Teams/7252-walker-elite.png?v=1'},
          ]
        };

    final r = rankings();
    await localizeLogos(r, web.path, client: client, log: (_) {});
    final teams = (r['teams'] as List).cast<Map<String, dynamic>>();
    final local = teams[0]['logo'] as String;
    expect(local, matches(RegExp(r'^logos/[0-9a-f]{16}\.jpg$')));
    expect(teams[1]['logo'], 'https://cdn.example/broken.png', reason: 'kept when it cannot be fetched');
    expect(teams[2]['logo'], isNull);
    expect(teams[3]['logo'], matches(RegExp(r'^logos/[0-9a-f]{16}\.jpg$')));
    final copy = img.decodeJpg(File('${web.path}/$local').readAsBytesSync())!;
    expect((copy.width, copy.height), (192, 96));
    expect(File('${web.path}/logos/stale.jpg').existsSync(), isFalse);

    // A second run reuses the copy.
    calls = 0;
    final again = rankings();
    await localizeLogos(again, web.path, client: client, log: (_) {});
    expect((again['teams'] as List).first['logo'], local);
    expect(calls, 1, reason: 'only the broken one is tried again');
  });

  test('transparent parts turn white', () {
    final clear = img.Image(width: 10, height: 10, numChannels: 4);
    final out = shrinkOnWhite(clear, 192);
    final p = out.getPixel(5, 5);
    expect((p.r, p.g, p.b), (255, 255, 255));
  });
}
