import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'screens/rankings_screen.dart';

void main() {
  runApp(const TeamRankApp());
}

/// Loads `data/rankings.json` from the same site the app is served from.
Future<RankingsData> loadRankings() async {
  final url = Uri.base.resolve('data/rankings.json');
  final res = await http.get(url.replace(queryParameters: {
    // The nightly job replaces the file; skip stale browser caches.
    't': '${DateTime.now().millisecondsSinceEpoch ~/ 600000}',
  }));
  if (res.statusCode != 200) {
    throw Exception('Could not load rankings (${res.statusCode})');
  }
  return RankingsData.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
}

class TeamRankApp extends StatelessWidget {
  const TeamRankApp({super.key, this.loader = loadRankings});

  final Future<RankingsData> Function() loader;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1B3A6B),
            brightness: b,
          ),
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'TeamRank: Louisiana 12U',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: RankingsScreen(loader: loader),
    );
  }
}
