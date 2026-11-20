import 'dart:io';
import 'package:flutter/material.dart';
import 'store.dart';

const kAccent = Color(0xFF8B5CF6);
const kPink = Color(0xFFEC4899);
const kBg = Color(0xFF0A0A18);
const kCard = Color(0xFF16162E);

const _palettes = <List<Color>>[
  [Color(0xFF8B5CF6), Color(0xFFEC4899)],
  [Color(0xFF06B6D4), Color(0xFF3B82F6)],
  [Color(0xFFF59E0B), Color(0xFFEF4444)],
  [Color(0xFF10B981), Color(0xFF06B6D4)],
  [Color(0xFFEC4899), Color(0xFFF97316)],
];

List<Color> paletteFor(String key) => _palettes[key.hashCode.abs() % _palettes.length];

LinearGradient gradientFor(String key) => LinearGradient(
      colors: paletteFor(key),
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

String fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

void toast(BuildContext c, String m) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1500),
    ));
}

class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child, this.tint = const Color(0xFF1E1140)});
  final Widget child;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint, kBg, kBg],
          stops: const [0, 0.5, 1],
        ),
      ),
      child: child,
    );
  }
}

class Cover extends StatelessWidget {
  const Cover(this.song, {super.key, this.size = 56, this.radius = 14});
  final Song? song;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(gradient: gradientFor(song?.title ?? '')),
      child: Center(
        child: Icon(Icons.music_note_rounded, color: Colors.white.withAlpha(230), size: size * 0.45),
      ),
    );
    final c = song?.cover;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: c == null
            ? fallback
            : Image.file(File(c), fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
      ),
    );
  }
}

Future<String?> askText(BuildContext c, String title, {String initial = '', String hint = ''}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(d, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: const Text('OK')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext c, String msg) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Confirmer')),
      ],
    ),
  );
  return r ?? false;
}

Future<void> addToPlaylistSheet(BuildContext c, List<Song> songs) {
  String msg(Playlist pl) =>
      songs.length == 1 ? 'Ajouté à ${pl.name}' : '${songs.length} titres ajoutés à ${pl.name}';
  return showModalBottomSheet<void>(
    context: c,
    backgroundColor: kCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (b) => ListenableBuilder(
      listenable: Store.i,
      builder: (_, __) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(b).size.height * 0.6),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  songs.length == 1 ? 'Ajouter à une playlist' : 'Ajouter ${songs.length} titres à une playlist',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const CircleAvatar(backgroundColor: kAccent, child: Icon(Icons.add, color: Colors.white)),
                title: const Text('Nouvelle playlist'),
                onTap: () async {
                  final n = await askText(b, 'Nouvelle playlist', hint: 'Nom de la playlist');
                  if (n == null || n.trim().isEmpty) return;
                  final pl = Store.i.createPlaylist(n);
                  Store.i.addAllToPlaylist(pl, songs);
                  if (b.mounted) Navigator.pop(b);
                  if (c.mounted) toast(c, msg(pl));
                },
              ),
              for (final pl in Store.i.playlists)
                ListTile(
                  leading: const Icon(Icons.queue_music_rounded),
                  title: Text(pl.name),
                  subtitle: Text('${pl.paths.length} titres'),
                  trailing: songs.every((s) => pl.paths.contains(s.path))
                      ? const Icon(Icons.check_circle, color: kAccent)
                      : null,
                  onTap: () {
                    Store.i.addAllToPlaylist(pl, songs);
                    Navigator.pop(b);
                    toast(c, msg(pl));
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
