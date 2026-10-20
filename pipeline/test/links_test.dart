import 'package:teamrank_pipeline/teamrank_pipeline.dart';
import 'package:test/test.dart';

Map<String, dynamic> doc(String type, List<String> keys, [String value = '']) => {
      'type': {'stringValue': type},
      'keys': {
        'arrayValue': {
          'values': [for (final k in keys) {'stringValue': k}]
        }
      },
      'value': {'stringValue': value},
    };

void main() {
  test('converts admin console links into aliases', () {
    final a = linksToAliases([
      doc('merge', ['otc:1', '2d:a']),
      doc('split', ['otc:2', '2d:b']),
      doc('name', ['otc:1'], 'Slidell Raptors'),
      doc('level', ['otc:3'], 'AAA'),
      doc('level', ['otc:4'], 'bogus'),
      doc('merge', ['otc:5']),
    ]);
    expect(a.merge, [
      ['otc:1', '2d:a']
    ]);
    expect(a.split, [
      ['otc:2', '2d:b']
    ]);
    expect(a.names, {'otc:1': 'Slidell Raptors'});
    expect(a.levels, {'otc:3': 'AAA'});
  });

  test('combine keeps both sets, the second winning conflicts', () {
    final a = Aliases(names: {'x': 'A'}, merge: [
      ['x', 'y']
    ]).combine(Aliases(names: {'x': 'B'}, levels: {'x': 'AA'}));
    expect(a.names['x'], 'B');
    expect(a.merge, hasLength(1));
    expect(a.levels['x'], 'AA');
  });
}
