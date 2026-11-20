import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'store.dart';

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
    }
    _broadcast();
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
