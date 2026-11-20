import 'dart:io';
import 'dart:ui' as ui;
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'store.dart';
import 'ui.dart' show paletteFor, paletteIndex;

Future<Uri> _defaultArt(String key) async {
  final dir = await getApplicationSupportDirectory();
  final f = File('${dir.path}/art_v1_${paletteIndex(key)}.png');
  if (!f.existsSync()) {
    const s = 512.0;
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.drawRect(
      const ui.Rect.fromLTWH(0, 0, s, s),
      ui.Paint()..shader = ui.Gradient.linear(ui.Offset.zero, const ui.Offset(s, s), paletteFor(key)),
    );
    final w = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
    ui.Offset p(double x, double y) => ui.Offset(x * s, y * s);
    for (final h in const [ui.Offset(0.36, 0.69), ui.Offset(0.68, 0.63)]) {
      c.drawOval(ui.Rect.fromCenter(center: p(h.dx, h.dy), width: 0.19 * s, height: 0.14 * s), w);
    }
    c.drawRect(ui.Rect.fromPoints(p(0.4225, 0.30), p(0.4475, 0.69)), w);
    c.drawRect(ui.Rect.fromPoints(p(0.7425, 0.24), p(0.7675, 0.63)), w);
    final beam = ui.Path()
      ..moveTo(p(0.4225, 0.285).dx, p(0.4225, 0.285).dy)
      ..lineTo(p(0.7675, 0.225).dx, p(0.7675, 0.225).dy)
      ..lineTo(p(0.7675, 0.295).dx, p(0.7675, 0.295).dy)
      ..lineTo(p(0.4225, 0.355).dx, p(0.4225, 0.355).dy)
      ..close();
    c.drawPath(beam, w);
    final img = await rec.endRecording().toImage(512, 512);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await f.writeAsBytes(bytes!.buffer.asUint8List());
  }
  return Uri.file(f.path);
}

class PlayerHandler extends BaseAudioHandler {
  PlayerHandler() {
    final pl = Store.i.player;
    pl.playbackEventStream.listen((_) => _broadcast());
    pl.playingStream.listen((_) => _broadcast());
    pl.durationStream.listen((d) {
      final m = mediaItem.value;
      if (m != null && d != null) mediaItem.add(m.copyWith(duration: d));
    });
    Store.i.addListener(_sync);
  }

  static const _close = MediaControl(
    androidIcon: 'drawable/ic_close',
    label: 'Fermer',
    action: MediaAction.stop,
  );

  String _key = '';
  String _path = '';

  void _sync() {
    final s = Store.i.current;
    if (s == null) {
      if (_key.isNotEmpty) {
        _key = '';
        _path = '';
        mediaItem.add(null);
        stop();
      }
      return;
    }
    final k = '${s.path}|${s.title}|${s.cover}';
    if (k != _key) {
      final same = _path == s.path;
      _key = k;
      _path = s.path;
      mediaItem.add(MediaItem(
        id: s.path,
        title: s.title,
        duration: same ? Store.i.player.duration : null,
        artUri: s.cover != null ? Uri.file(s.cover!) : null,
      ));
      _setArt(s);
    }
    _broadcast();
  }

  Future<void> _setArt(Song s) async {
    if (s.cover != null) return;
    try {
      final u = await _defaultArt(s.title);
      final m = mediaItem.value;
      if (m != null && m.id == s.path && m.artUri == null) mediaItem.add(m.copyWith(artUri: u));
    } catch (_) {}
  }

  void _broadcast() {
    final pl = Store.i.player;
    final playing = pl.playing;
    playbackState.add(PlaybackState(
      controls: playing
          ? [
              MediaControl.skipToPrevious,
              MediaControl.rewind,
              MediaControl.pause,
              MediaControl.fastForward,
              MediaControl.skipToNext,
            ]
          : [
              MediaControl.skipToPrevious,
              MediaControl.play,
              MediaControl.skipToNext,
              _close,
            ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: playing ? const [0, 2, 4] : const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[pl.processingState]!,
      playing: playing,
      updatePosition: pl.position,
      bufferedPosition: pl.bufferedPosition,
      speed: pl.speed,
    ));
  }

  @override
  Future<void> play() async {
    if (!Store.i.player.playing) Store.i.player.play();
  }

  @override
  Future<void> pause() => Store.i.player.pause();

  @override
  Future<void> stop() async {
    await Store.i.player.pause();
    await super.stop();
  }

  @override
  Future<void> skipToNext() => Store.i.next();

  @override
  Future<void> skipToPrevious() => Store.i.previous();

  @override
  Future<void> rewind() => Store.i.skip(-Store.i.step);

  @override
  Future<void> fastForward() => Store.i.skip(Store.i.step);

  @override
  Future<void> seek(Duration position) => Store.i.player.seek(position);
}
