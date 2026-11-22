import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'player.dart';
import 'store.dart';
import 'ui.dart';

class _Cancelled implements Exception {}

class _Item {
  _Item({
    required this.title,
    required this.subtitle,
    required this.ext,
    required this.mime,
    required this.total,
    required this.open,
    this.thumb,
    this.attempts = 1,
  });
  final String title;
  final String subtitle;
  final String ext;
  final String mime;
  final int total;
  final String? thumb;
  final Future<Stream<List<int>>> Function(int attempt) open;
  final int attempts;
}

Stream<List<int>> _httpGet(Uri uri) async* {
  final c = HttpClient();
  try {
    final r = await (await c.getUrl(uri)).close();
    yield* r;
  } finally {
    c.close(force: true);
  }
}

class DownloadTab extends StatefulWidget {
  const DownloadTab({super.key});

  @override
  State<DownloadTab> createState() => _DownloadTabState();
}

class _DownloadTabState extends State<DownloadTab> {
  final ctl = TextEditingController();
  final progress = ValueNotifier<(double?, int)>((0, 0));
  final _yt = yt.YoutubeExplode();
  bool busy = false;
  bool downloading = false;
  bool importing = false;
  bool finished = false;
  bool cancel = false;
  String? error;
  _Item? item;
  Song? done;

  @override
  void dispose() {
    _yt.close();
    ctl.dispose();
    progress.dispose();
    super.dispose();
  }

  String _msg(Object e) {
    if (e is MissingPluginException) {
      return 'Installation incomplète : lancez « dart tool/setup.dart » puis réinstallez l’application.';
    }
    if (e is SocketException) return 'Pas de connexion internet.';
    if (e is TimeoutException) {
      return 'Le téléchargement est bloqué : YouTube ne renvoie pas les données. Réessayez plus tard, ou mettez à jour la bibliothèque avec « flutter pub upgrade youtube_explode_dart ».';
    }
    if (e is String) return e;
    if (e is PlatformException) return e.message ?? 'Erreur inconnue';
    final t = e.toString();
    return 'Impossible de traiter ce lien. ${t.length > 160 ? t.substring(0, 160) : t}';
  }

  String _safe(String s) {
    final t = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return 'musique';
    return t.length > 90 ? t.substring(0, 90).trim() : t;
  }

  String _mb(int b) => '${(b / 1048576).toStringAsFixed(1)} Mo';

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text;
    if (t != null) setState(() => ctl.text = t.trim());
  }

  Future<yt.StreamManifest> _manifest(yt.VideoId id, bool vr) {
    return vr
        ? _yt.videos.streams.getManifest(id, ytClients: [yt.YoutubeApiClient.androidVr])
        : _yt.videos.streams.getManifest(id);
  }

  Future<(yt.StreamManifest, bool)> _manifestAuto(yt.VideoId id) async {
    try {
      return (await _manifest(id, true), true);
    } catch (_) {
      return (await _manifest(id, false), false);
    }
  }

  yt.AudioOnlyStreamInfo _pick(yt.StreamManifest manifest) {
    final all = manifest.audioOnly.toList();
    if (all.isEmpty) throw 'Aucune piste audio disponible pour cette vidéo.';
    final mp4 = all.where((s) => s.container.name == 'mp4').toList();
    final pool = mp4.isNotEmpty ? mp4 : all;
    pool.sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
    return pool.first;
  }

  Future<_Item> _analyzeYoutube(String link) async {
    final video = await _yt.videos.get(link);
    final (manifest, usedVr) = await _manifestAuto(video.id);
    final s = _pick(manifest);
    final isMp4 = s.container.name == 'mp4';
    final total = s.size.totalBytes;
    final d = video.duration;
    return _Item(
      title: video.title,
      subtitle: [video.author, if (d != null) fmt(d), _mb(total)].join(' · '),
      thumb: video.thumbnails.highResUrl,
      ext: isMp4 ? 'm4a' : s.container.name,
      mime: isMp4 ? 'audio/mp4' : 'audio/${s.container.name}',
      total: total,
      attempts: 2,
      open: (attempt) async {
        if (attempt == 0) return _yt.videos.streams.get(s);
        final m = await _manifest(video.id, !usedVr);
        return _yt.videos.streams.get(_pick(m));
      },
    );
  }

  Future<_Item> _analyzeDirect(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) throw 'Lien invalide.';
    const known = {
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'aac': 'audio/aac',
      'wav': 'audio/wav',
      'flac': 'audio/flac',
      'ogg': 'audio/ogg',
      'opus': 'audio/ogg',
    };
    const byMime = {
      'audio/mpeg': 'mp3',
      'audio/mp4': 'm4a',
      'audio/aac': 'aac',
      'audio/wav': 'wav',
      'audio/x-wav': 'wav',
      'audio/flac': 'flac',
      'audio/ogg': 'ogg',
    };
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(uri)).close();
      if (res.statusCode != 200) throw 'Le serveur a répondu ${res.statusCode}.';
      var ext = p.extension(uri.path).toLowerCase().replaceFirst('.', '');
      if (!known.containsKey(ext)) ext = byMime[res.headers.contentType?.mimeType ?? ''] ?? '';
      if (ext.isEmpty) {
        throw 'Ce lien n’est pas pris en charge. Utilisez un lien YouTube ou un lien direct vers un fichier audio (mp3, m4a...).';
      }
      final total = res.contentLength;
      var name = p.basenameWithoutExtension(uri.path);
      try {
        name = Uri.decodeComponent(name);
      } catch (_) {}
      return _Item(
        title: name.isEmpty ? 'musique' : name,
        subtitle: ['Fichier audio ${ext.toUpperCase()}', if (total > 0) _mb(total)].join(' · '),
        ext: ext,
        mime: known[ext]!,
        total: total,
        open: (_) async => _httpGet(uri),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _analyze() async {
    final link = ctl.text.trim();
    if (link.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
      item = null;
      finished = false;
      done = null;
    });
    try {
      final it = yt.VideoId.parseVideoId(link) != null ? await _analyzeYoutube(link) : await _analyzeDirect(link);
      if (mounted) setState(() => item = it);
    } catch (e) {
      if (mounted) setState(() => error = _msg(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _fetch(_Item it, int attempt, File file) async {
    final stream = (await it.open(attempt).timeout(const Duration(seconds: 30)))
        .timeout(const Duration(seconds: 25));
    final sink = file.openWrite();
    var got = 0;
    var last = -1;
    try {
      await for (final chunk in stream) {
        if (cancel) throw _Cancelled();
        sink.add(chunk);
        got += chunk.length;
        final pc = it.total > 0 ? got * 100 ~/ it.total : got ~/ 131072;
        if (pc != last) {
          last = pc;
          progress.value = (it.total > 0 ? (got / it.total).clamp(0.0, 1.0).toDouble() : null, got);
        }
      }
    } finally {
      await sink.close();
    }
    if (got == 0) throw 'Aucune donnée reçue.';
  }

  Future<void> _download() async {
    final it = item;
    if (it == null) return;
    cancel = false;
    progress.value = (0, 0);
    setState(() {
      downloading = true;
      importing = false;
      finished = false;
      error = null;
    });
    File? tmp;
    try {
      final dir = await getTemporaryDirectory();
      final f = File(p.join(dir.path, 'dl_${DateTime.now().millisecondsSinceEpoch}.${it.ext}'));
      tmp = f;
      for (var attempt = 0; attempt < it.attempts; attempt++) {
        try {
          await _fetch(it, attempt, f);
          break;
        } on _Cancelled {
          rethrow;
        } catch (e) {
          if (attempt == it.attempts - 1) rethrow;
          progress.value = (0, 0);
        }
      }
      if (mounted) setState(() => importing = true);
      await Store.i.importAudio(f.path, '${_safe(it.title)}.${it.ext}', it.title, it.mime);
      Song? found;
      for (final s in Store.i.songs) {
        if (s.title == it.title && (found == null || s.added > found.added)) found = s;
      }
      if (mounted) {
        setState(() {
          finished = true;
          done = found;
        });
        toast(context, 'Ajoutée à votre bibliothèque');
      }
    } on _Cancelled {
      if (mounted) toast(context, 'Téléchargement annulé');
    } catch (e) {
      if (mounted) setState(() => error = _msg(e));
    } finally {
      try {
        tmp?.deleteSync();
      } catch (_) {}
      if (mounted) {
        setState(() {
          downloading = false;
          importing = false;
        });
      }
    }
  }

  Widget _action(_Item it) {
    if (downloading) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ValueListenableBuilder<(double?, int)>(
          valueListenable: progress,
          builder: (_, st, __) {
            final v = st.$1;
            final b = st.$2;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: importing ? null : (b == 0 ? null : v),
                  minHeight: 8,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(kAccent),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                importing
                    ? 'Ajout à la bibliothèque…'
                    : b == 0
                        ? 'Connexion…'
                        : v == null
                            ? 'Téléchargement… ${_mb(b)}'
                            : 'Téléchargement… ${(v * 100).round()} % · ${_mb(b)}',
                style: const TextStyle(color: Colors.white70),
              ),
            ]);
          },
        ),
        if (!importing)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => cancel = true, child: const Text('Annuler')),
          ),
      ]);
    }
    if (finished) {
      return Row(children: [
        const Icon(Icons.check_circle_rounded, color: Color(0xFF34D399)),
        const SizedBox(width: 8),
        const Expanded(child: Text('Ajoutée à votre bibliothèque', style: TextStyle(fontWeight: FontWeight.w600))),
        if (done != null)
          FilledButton.icon(
            onPressed: () {
              Store.i.play([done!], 0);
              openPlayer(context);
            },
            style: FilledButton.styleFrom(backgroundColor: kAccent),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Lire'),
          ),
      ]);
    }
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: _download,
        style: FilledButton.styleFrom(
          backgroundColor: kPink,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: const Icon(Icons.download_rounded),
        label: const Text('Télécharger l’audio', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    );
  }

  Widget _card(_Item it) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withAlpha(18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (it.thumb != null)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.network(
              it.thumb!,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: BoxDecoration(gradient: gradientFor(it.title)),
                child: const Center(child: Icon(Icons.music_note_rounded, size: 48, color: Colors.white)),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              it.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.25),
            ),
            const SizedBox(height: 6),
            Text(it.subtitle, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            _action(it),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final it = item;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text('Télécharger', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            'Collez un lien YouTube ou un lien direct vers un fichier audio (mp3, m4a...).',
            style: TextStyle(color: Colors.white54),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: ctl,
          enabled: !downloading,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _analyze(),
          decoration: InputDecoration(
            hintText: 'https://...',
            prefixIcon: const Icon(Icons.link_rounded),
            suffixIcon: IconButton(onPressed: _paste, icon: const Icon(Icons.content_paste_rounded)),
            filled: true,
            fillColor: kCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: busy || downloading ? null : _analyze,
            style: FilledButton.styleFrom(
              backgroundColor: kAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text('Analyser le lien', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withAlpha(30),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.redAccent.withAlpha(120)),
              ),
              child: Text(error!, style: const TextStyle(fontSize: 13)),
            ),
          ),
        if (it != null) ...[
          const SizedBox(height: 20),
          _card(it),
        ],
        const SizedBox(height: 24),
        const Text(
          'Téléchargez uniquement du contenu dont vous détenez les droits ou dont la copie est autorisée.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ]),
    );
  }
}
