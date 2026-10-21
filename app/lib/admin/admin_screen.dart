import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../models.dart';

/// Public web config for the `teamrank-la` Firebase project. These values
/// identify the project; access is controlled by `firestore.rules`.
const firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyDjWItNssxE_tXPiXNvFpN8LHTuA8_ryhY',
  appId: '1:161376992197:web:4c6d77e6378fff5dc4e9ac',
  messagingSenderId: '161376992197',
  projectId: 'teamrank-la',
  authDomain: 'teamrank-la.firebaseapp.com',
  storageBucket: 'teamrank-la.firebasestorage.app',
);

/// The admin console at `/admin`: link listings of the same team across
/// orgs, split wrong matches, rename teams and move them between the AA,
/// AAA and Majors lists. Changes are saved to Firestore's `links` collection,
/// and the next scheduled update applies them.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.loader});

  final Future<RankingsData> Function() loader;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late final Future<void> _init = Firebase.initializeApp(options: firebaseOptions);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TeamRank admin'),
        actions: [
          StreamBuilder<User?>(
            stream: _init.asStream().asyncExpand((_) => FirebaseAuth.instance.authStateChanges()),
            builder: (context, snap) => snap.data == null
                ? const SizedBox()
                : TextButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: const Text('Sign out'),
                  ),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _init,
        builder: (context, init) {
          if (init.hasError) return _Center(text: 'Could not start: ${init.error}');
          if (init.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snap) {
              final user = snap.data;
              if (user == null) return const _SignIn();
              return _AdminGate(user: user, loader: widget.loader);
            },
          );
        },
      ),
    );
  }
}

class _SignIn extends StatefulWidget {
  const _SignIn();

  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  String? _error;

  Future<void> _signIn() async {
    setState(() => _error = null);
    try {
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    }
  }

  @override
  Widget build(BuildContext context) => _Center(
        text: 'Sign in with the Google account that has admin access.',
        child: Column(children: [
          FilledButton.icon(
            onPressed: _signIn,
            icon: const Icon(Icons.login),
            label: const Text('Sign in with Google'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ]),
      );
}

/// Shows the console only to accounts listed in Firestore's `admins`.
class _AdminGate extends StatelessWidget {
  const _AdminGate({required this.user, required this.loader});

  final User user;
  final Future<RankingsData> Function() loader;

  Future<bool> _isAdmin() async {
    try {
      final doc = await FirebaseFirestore.instance.doc('admins/${user.email}').get();
      return doc.exists;
    } on FirebaseException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(bool, RankingsData)>(
      future: Future.wait([_isAdmin(), loader()]).then((r) => (r[0] as bool, r[1] as RankingsData)),
      builder: (context, snap) {
        if (snap.hasError) return _Center(text: 'Could not load: ${snap.error}');
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final (isAdmin, data) = snap.data!;
        if (!isAdmin) {
          return _Center(text: '${user.email} does not have admin access.');
        }
        return _Console(data: data, email: user.email!);
      },
    );
  }
}

/// A saved change from the `links` collection.
class _Link {
  _Link(this.id, this.type, this.keys, this.value, this.email, this.createdAt);

  final String id;
  final String type;
  final List<String> keys;
  final String value;
  final String email;
  final DateTime? createdAt;

  factory _Link.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return _Link(
      d.id,
      m['type'] as String? ?? '',
      (m['keys'] as List? ?? []).cast<String>(),
      m['value'] as String? ?? '',
      m['email'] as String? ?? '',
      (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class _Console extends StatelessWidget {
  const _Console({required this.data, required this.email});

  final RankingsData data;
  final String email;

  CollectionReference<Map<String, dynamic>> get _links =>
      FirebaseFirestore.instance.collection('links');

  /// Every org listing on the site, keyed by listing key.
  Map<String, ({TeamSource source, Team team})> get _listings => {
        for (final t in data.teams)
          for (final s in t.sources)
            if (s.key.isNotEmpty) s.key: (source: s, team: t),
      };

  Future<void> _save(BuildContext context, String type, List<String> keys, [String value = '']) async {
    await _links.add({
      'type': type,
      'keys': keys,
      'value': value,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved. It takes effect at the next update (Sat, Sun, Mon or Wed night).')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _links.orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return _Center(text: 'Could not load saved changes: ${snap.error}');
        final links = (snap.data?.docs ?? []).map(_Link.fromDoc).toList();
        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              const TabBar(tabs: [
                Tab(text: 'Suggested matches'),
                Tab(text: 'Link or edit teams'),
                Tab(text: 'Saved changes'),
              ]),
              Expanded(
                child: TabBarView(children: [
                  _Suggestions(data: data, links: links, onSave: (t, k) => _save(context, t, k)),
                  _Editor(listings: _listings, data: data, onSave: (t, k, [v = '']) => _save(context, t, k, v)),
                  _SavedLinks(links: links, listings: _listings, onDelete: (id) => _links.doc(id).delete()),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.data, required this.links, required this.onSave});

  final RankingsData data;
  final List<_Link> links;
  final void Function(String type, List<String> keys) onSave;

  @override
  Widget build(BuildContext context) {
    // Hide suggestions already answered with a saved merge or split.
    final answered = {
      for (final l in links)
        if (l.type == 'merge' || l.type == 'split') (l.keys.toList()..sort()).join('|')
    };
    final open = data.suggestions
        .where((s) => !answered.contains((s.keys.toList()..sort()).join('|')))
        .toList();
    if (open.isEmpty) return const _Center(text: 'No suggested matches right now.');
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: open.length,
      itemBuilder: (context, i) {
        final s = open[i];
        return Card.outlined(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.reason, style: Theme.of(context).textTheme.labelMedium),
                for (final l in s.listings)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.name),
                    subtitle: Text('${sourceLabel(l.source)} · ${[l.city, l.state].where((x) => x.isNotEmpty).join(', ')}'
                        ' · ${l.ageClass} · ${l.events} events'),
                  ),
                Wrap(spacing: 8, children: [
                  FilledButton(onPressed: () => onSave('merge', s.keys), child: const Text('Same team')),
                  OutlinedButton(onPressed: () => onSave('split', s.keys), child: const Text('Different teams')),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Editor extends StatefulWidget {
  const _Editor({required this.listings, required this.data, required this.onSave});

  final Map<String, ({TeamSource source, Team team})> listings;
  final RankingsData data;
  final void Function(String type, List<String> keys, [String value]) onSave;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  Team? _a;
  Team? _b;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<String> _keys(Team t) => [for (final s in t.sources) if (s.key.isNotEmpty) s.key];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = _a, b = _b;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Link two teams that are really the same team', style: t.titleMedium),
        const SizedBox(height: 8),
        _TeamPicker(teams: widget.data.teams, label: 'First team', onPicked: (x) => setState(() => _a = x)),
        const SizedBox(height: 8),
        _TeamPicker(teams: widget.data.teams, label: 'Second team', onPicked: (x) => setState(() => _b = x)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: a == null || b == null || a.id == b.id
                ? null
                : () => widget.onSave('merge', [..._keys(a), ..._keys(b)]),
            child: const Text('Link as one team'),
          ),
        ),
        const Divider(height: 40),
        Text('Edit one team', style: t.titleMedium),
        const SizedBox(height: 4),
        Text('Uses the first team picked above.', style: t.bodySmall),
        if (a != null) ...[
          const SizedBox(height: 8),
          for (final s in a.sources) Text('• ${s.label}: ${s.name} (${s.ageClass})'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: () => widget.onSave('level', _keys(a), 'AA'), child: const Text('Move to AA list')),
            OutlinedButton(onPressed: () => widget.onSave('level', _keys(a), 'AAA'), child: const Text('Move to AAA list')),
            OutlinedButton(
                onPressed: () => widget.onSave('level', _keys(a), 'Majors'), child: const Text('Move to Majors list')),
            for (var age = 10; age <= 14; age++)
              if (age != a.age)
                OutlinedButton(
                    onPressed: () => widget.onSave('age', _keys(a), '$age'), child: Text('List as ${ageLabel(age)}')),
            if (a.sources.length > 1)
              OutlinedButton(
                onPressed: () => widget.onSave('split', _keys(a)),
                child: const Text('These listings are different teams'),
              ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Display name', border: OutlineInputBorder(), isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () {
                if (_name.text.trim().isNotEmpty) widget.onSave('name', _keys(a).take(1).toList(), _name.text.trim());
              },
              child: const Text('Rename'),
            ),
          ]),
        ],
      ],
    );
  }
}

class _TeamPicker extends StatelessWidget {
  const _TeamPicker({required this.teams, required this.label, required this.onPicked});

  final List<Team> teams;
  final String label;
  final ValueChanged<Team?> onPicked;

  String _describe(Team t) =>
      '${t.name} · ${t.hometown} · ${t.sources.map((s) => s.source.toUpperCase()).toSet().join('+')}';

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Team>(
      displayStringForOption: _describe,
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<Team>.empty();
        return teams.where((t) => t.name.toLowerCase().contains(q) || t.city.toLowerCase().contains(q)).take(20);
      },
      onSelected: onPicked,
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
        controller: controller,
        focusNode: focus,
        onChanged: (_) => onPicked(null),
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Search team or town',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _SavedLinks extends StatelessWidget {
  const _SavedLinks({required this.links, required this.listings, required this.onDelete});

  final List<_Link> links;
  final Map<String, ({TeamSource source, Team team})> listings;
  final void Function(String id) onDelete;

  String _name(String key) {
    final l = listings[key];
    return l == null ? key : '${l.source.name} (${l.source.source.toUpperCase()})';
  }

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) return const _Center(text: 'No saved changes yet.');
    final dates = MaterialLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final l in links)
          ListTile(
            title: Text(switch (l.type) {
              'merge' => 'Same team: ${l.keys.map(_name).join(' = ')}',
              'split' => 'Different teams: ${l.keys.map(_name).join(' / ')}',
              'name' => 'Rename ${l.keys.map(_name).join(', ')} to "${l.value}"',
              'level' => 'Put ${l.keys.map(_name).join(', ')} in ${levelLabel(l.value)}',
              'age' => 'List ${l.keys.map(_name).join(', ')} as ${l.value}U',
              _ => l.type,
            }),
            subtitle: Text([
              if (l.createdAt != null) dates.formatMediumDate(l.createdAt!),
              l.email,
            ].join(' · ')),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => onDelete(l.id),
            ),
          ),
      ],
    );
  }
}

class _Center extends StatelessWidget {
  const _Center({required this.text, this.child});

  final String text;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text, textAlign: TextAlign.center),
            if (child != null) ...[const SizedBox(height: 16), child!],
          ]),
        ),
      );
}
