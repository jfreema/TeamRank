import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Copies team logos onto the site itself, as small JPEGs on white (they are
/// shown in a white circle anyway), and points each team at its copy.
///
/// The orgs' image hosts send no CORS headers, so the app could only show
/// their logos as browser `<img>` elements laid over the page, and Safari
/// sometimes left the wrong picture in a row after the list changed. Logos
/// from the site's own host are drawn like any other image.
///
/// Files are named by a hash of the source URL, so each logo is fetched once.
/// A logo that cannot be fetched or read keeps its original URL. Files no
/// team uses any more are deleted.
Future<void> localizeLogos(Map<String, dynamic> rankings, String webDir,
    {http.Client? client, int size = 192, void Function(String) log = print}) async {
  final http.Client c = client ?? http.Client();
  final dir = Directory('$webDir/logos')..createSync(recursive: true);
  final used = <String>{};
  var fetched = 0, failed = 0;
  try {
    for (final team in (rankings['teams'] as List).cast<Map<String, dynamic>>()) {
      final url = team['logo'];
      if (url is! String || !url.startsWith('http')) continue;
      final name = '${_hash(url)}.jpg';
      final file = File('${dir.path}/$name');
      if (!file.existsSync()) {
        try {
          final res = await c.get(Uri.parse(url));
          if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
          final picture = img.decodeImage(res.bodyBytes);
          if (picture == null) throw const FormatException('not an image');
          file.writeAsBytesSync(img.encodeJpg(shrinkOnWhite(picture, size), quality: 85));
          fetched++;
        } catch (e) {
          failed++;
          log('logo $url: $e');
          continue;
        }
      }
      used.add(name);
      team['logo'] = 'logos/$name';
    }
  } finally {
    if (client == null) c.close();
  }
  for (final f in dir.listSync().whereType<File>()) {
    if (!used.contains(f.uri.pathSegments.last)) f.deleteSync();
  }
  log('logos: ${used.length} on the site, $fetched new, $failed kept at their org');
}

/// [picture] scaled to fit a [size] square, transparent parts made white.
img.Image shrinkOnWhite(img.Image picture, int size) {
  final scaled = picture.width > size || picture.height > size
      ? img.copyResize(picture,
          width: picture.width >= picture.height ? size : null,
          height: picture.height > picture.width ? size : null,
          interpolation: img.Interpolation.average)
      : picture;
  final out = img.Image(width: scaled.width, height: scaled.height);
  img.fill(out, color: img.ColorRgb8(255, 255, 255));
  return img.compositeImage(out, scaled);
}

/// FNV-1a, 64 bits, as hex: short, stable file names.
String _hash(String s) {
  var h = 0xcbf29ce484222325;
  for (final b in s.codeUnits) {
    h ^= b;
    h *= 0x100000001b3;
  }
  // Dart ints are signed, so print the two halves.
  String half(int v) => v.toRadixString(16).padLeft(8, '0');
  return half((h >>> 32) & 0xFFFFFFFF) + half(h & 0xFFFFFFFF);
}
