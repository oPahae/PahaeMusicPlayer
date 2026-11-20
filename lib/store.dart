import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BestPart {
  BestPart(this.label, this.seconds);
  String label;
  int seconds;

  Map<String, dynamic> toJson() => {'l': label, 's': seconds};

  factory BestPart.fromJson(Map<String, dynamic> j) => BestPart(j['l'] as String, j['s'] as int);
}

class Song {
  Song(this.path, this.title, {this.uri, this.added = 0, this.cover, List<BestPart>? parts})
      : parts = parts ?? [];
  final String path;
  final String? uri;
  final int added;
  String title;
  String? cover;
  List<BestPart> parts;

  int? get mediaId => uri == null ? null : int.tryParse(uri!.split('/').last);
}

class Playlist {
  Playlist(this.id, this.name, [List<String>? paths]) : paths = paths ?? [];
  final String id;
  String name;
  List<String> paths;

  Map<String, dynamic> toJson() => {'i': id, 'n': name, 'p': paths};

  factory Playlist.fromJson(Map<String, dynamic> j) =>
      Playlist(j['i'] as String, j['n'] as String, (j['p'] as List).cast<String>().toList());
}

class Store extends ChangeNotifier {
  Store._();
  static final Store i = Store._();

  final AudioPlayer player = AudioPlayer();
  List<Song> songs = [];
  List<Playlist> playlists = [];
  List<Song> queue = [];
  int index = -1;
  bool loading = true;
  bool denied = false;
  bool setupMissing = false;
  bool repeatOne = false;
  String? error;
  String sort = 'date_desc';
  int step = 10;

  static const _ch = MethodChannel('music/scan');

  late SharedPreferences _prefs;
  Map<String, dynamic> _meta = {};

  static const _ext = {'.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg', '.opus'};
  static const _skip = ['android', 'whatsapp', 'ringtones', 'notifications', 'alarms'];

  Song? get current => index >= 0 && index < queue.length ? queue[index] : null;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    sort = _prefs.getString('sort') ?? 'date_desc';
    final m = _prefs.getString('meta');
    if (m != null) _meta = jsonDecode(m) as Map<String, dynamic>;
    final pl = _prefs.getString('playlists');
    if (pl != null) {
      playlists = (jsonDecode(pl) as List)
          .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) next();
    });
    await scan();
  }

  Future<void> scan() async {
    loading = true;
    notifyListeners();
    try {
      await _ch.invokeMethod<String>('ping');
      setupMissing = false;
    } on MissingPluginException {
      setupMissing = true;
    } catch (_) {}
    final a = await Permission.audio.request();
    final s = await Permission.storage.request();
    final ok = a.isGranted || s.isGranted;
    denied = !ok;
    await Permission.notification.request();
    final found = <String, (String, String?, int)>{};
    if (ok) {
      try {
        final r = await _ch.invokeMethod<List<dynamic>>('songs');
        for (final e in r ?? <dynamic>[]) {
          final m = Map<String, dynamic>.from(e as Map);
          final path = m['path'] as String;
          found[path] = (
            (m['title'] as String?) ?? p.basenameWithoutExtension(path),
            'content://media/external/audio/media/${m['id']}',
            (m['added'] as num?)?.toInt() ?? 0,
          );
        }
      } catch (_) {}
      if (found.isEmpty) {
        final out = <String>[];
        await _walk(Directory('/storage/emulated/0'), out);
        for (final x in out) {
          var t = 0;
          try {
            t = File(x).statSync().modified.millisecondsSinceEpoch ~/ 1000;
          } catch (_) {}
          found[x] = (p.basenameWithoutExtension(x), null, t);
        }
      }
    }
    songs = found.entries.map((e) => _build(e.key, e.value.$1, e.value.$2, e.value.$3)).toList();
    _applySort();
    loading = false;
    notifyListeners();
  }

  Future<void> _walk(Directory d, List<String> out) async {
    try {
      await for (final e in d.list(followLinks: false)) {
        final name = p.basename(e.path).toLowerCase();
        if (e is Directory) {
          if (name.startsWith('.') || _skip.contains(name)) continue;
          await _walk(e, out);
        } else if (e is File && _ext.contains(p.extension(name))) {
          if (await e.length() > 300 * 1024) out.add(e.path);
        }
      }
    } catch (_) {}
  }

  Song _build(String path, String title, String? uri, int added) {
    final m = _meta[path] as Map<String, dynamic>?;
    final s = Song(path, (m?['t'] as String?) ?? title, uri: uri, added: added);
    if (m != null) {
      final c = m['c'] as String?;
      if (c != null && File(c).existsSync()) s.cover = c;
      s.parts = ((m['p'] as List?) ?? [])
          .map((e) => BestPart.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return s;
  }

  void _applySort() {
    songs.sort((a, b) {
      switch (sort) {
        case 'date_asc':
          return a.added.compareTo(b.added);
        case 'name_asc':
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case 'name_desc':
          return b.title.toLowerCase().compareTo(a.title.toLowerCase());
        default:
          return b.added.compareTo(a.added);
      }
    });
  }

  void setSort(String v) {
    sort = v;
    _applySort();
    _prefs.setString('sort', v);
    notifyListeners();
  }

  Future<void> _save() async {
    for (final s in songs) {
      _meta[s.path] = {'t': s.title, 'c': s.cover, 'p': s.parts.map((e) => e.toJson()).toList()};
    }
    await _prefs.setString('meta', jsonEncode(_meta));
    await _prefs.setString('playlists', jsonEncode(playlists.map((e) => e.toJson()).toList()));
  }

  void _commit() {
    notifyListeners();
    _save();
  }

  Future<void> play(List<Song> q, int i) async {
    queue = List.of(q);
    index = i;
    await _load();
  }

  Future<void> _load() async {
    final s = current;
    if (s == null) return;
    error = null;
    notifyListeners();
    try {
      if (s.uri != null) {
        await player.setAudioSource(AudioSource.uri(Uri.parse(s.uri!)));
      } else {
        await player.setFilePath(s.path);
      }
    } catch (_) {
      try {
        await player.setFilePath(s.path);
      } catch (e) {
        error = 'Lecture impossible : $e';
        notifyListeners();
        return;
      }
    }
    player.play();
  }

  Future<void> next() async {
    if (queue.isEmpty) return;
    index = (index + 1) % queue.length;
    await _load();
  }

  Future<void> previous() async {
    if (queue.isEmpty) return;
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
      return;
    }
    index = (index - 1 + queue.length) % queue.length;
    await _load();
  }

  Future<void> skip(int seconds) async {
    final d = player.duration ?? Duration.zero;
    var t = player.position + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (t > d) t = d;
    await player.seek(t);
  }

  Future<void> toggle() async {
    if (player.playing) {
      await player.pause();
    } else {
      player.play();
    }
  }

  Future<void> jumpTo(BestPart part) async {
    await player.seek(Duration(seconds: part.seconds));
    if (!player.playing) player.play();
  }

  Future<void> toggleRepeat() async {
    repeatOne = !repeatOne;
    await player.setLoopMode(repeatOne ? LoopMode.one : LoopMode.off);
    notifyListeners();
  }

  void setStep(int v) {
    step = v;
    notifyListeners();
  }

  void rename(Song s, String t) {
    if (t.trim().isEmpty) return;
    s.title = t.trim();
    _commit();
  }

  Future<void> pickCover(Song s) async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200);
    if (x == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final f = await File(x.path)
        .copy(p.join(dir.path, 'cover_${DateTime.now().millisecondsSinceEpoch}.jpg'));
    s.cover = f.path;
    _commit();
  }

  void savePart(Song s, BestPart? old, String label, int seconds) {
    if (old == null) {
      s.parts.add(BestPart(label, seconds));
    } else {
      old.label = label;
      old.seconds = seconds;
    }
    _commit();
  }

  void deletePart(Song s, BestPart part) {
    s.parts.remove(part);
    _commit();
  }

  Future<String?> deleteSongs(List<Song> list) async {
    final ids = [
      for (final s in list)
        if (s.mediaId != null) s.mediaId!
    ];
    String? err;
    if (ids.isNotEmpty) {
      try {
        final r = await _ch.invokeMethod<bool>('delete', {'ids': ids});
        if (r != true) err = 'Suppression annulée';
      } on MissingPluginException {
        err = 'Installation incomplète : lancez « dart tool/setup.dart » puis réinstallez l’application';
      } on PlatformException catch (e) {
        err = 'Erreur : ${e.message}';
      } catch (e) {
        err = 'Erreur : $e';
      }
    }
    for (final s in list.where((s) => s.mediaId == null)) {
      try {
        File(s.path).deleteSync();
      } catch (_) {
        err = 'Fichier impossible à supprimer';
      }
    }
    if (err != null) return err;
    final paths = {for (final s in list) s.path};
    final cur = current?.path;
    songs.removeWhere((s) => paths.contains(s.path));
    for (final pl in playlists) {
      pl.paths.removeWhere(paths.contains);
    }
    if (cur != null) {
      if (paths.contains(cur)) {
        await player.stop();
        queue = [];
        index = -1;
      } else {
        queue = queue.where((s) => !paths.contains(s.path)).toList();
        index = queue.indexWhere((s) => s.path == cur);
      }
    }
    for (final x in paths) {
      _meta.remove(x);
    }
    _commit();
    return null;
  }

  Playlist createPlaylist(String name) {
    final pl = Playlist(DateTime.now().microsecondsSinceEpoch.toString(), name.trim());
    playlists.add(pl);
    _commit();
    return pl;
  }

  void renamePlaylist(Playlist pl, String name) {
    if (name.trim().isEmpty) return;
    pl.name = name.trim();
    _commit();
  }

  void deletePlaylist(Playlist pl) {
    playlists.remove(pl);
    _commit();
  }

  void addAllToPlaylist(Playlist pl, List<Song> list) {
    for (final s in list) {
      if (!pl.paths.contains(s.path)) pl.paths.add(s.path);
    }
    _commit();
  }

  void removeFromPlaylist(Playlist pl, String path) {
    pl.paths.remove(path);
    _commit();
  }

  List<Song> songsOf(Playlist pl) {
    final m = {for (final s in songs) s.path: s};
    return [
      for (final x in pl.paths)
        if (m[x] != null) m[x]!
    ];
  }
}
