import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'store.dart';
import 'ui.dart';

void openPlayer(BuildContext c) {
  Navigator.of(c).push(PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) => const PlayerPage(),
    transitionsBuilder: (_, a, __, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ));
}

Future<void> partDialog(BuildContext c, Song s, {BestPart? part}) {
  final name = TextEditingController(text: part?.label ?? 'Best Part ${s.parts.length + 1}');
  final total = part?.seconds ?? Store.i.player.position.inSeconds;
  final min = TextEditingController(text: '${total ~/ 60}');
  final sec = TextEditingController(text: '${total % 60}');
  return showDialog<void>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(part == null ? 'Nouvelle best part' : 'Modifier la best part'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: min,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Minutes'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: sec,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Secondes'),
              ),
            ),
          ]),
        ],
      ),
      actions: [
        if (part != null)
          TextButton(
            onPressed: () {
              Store.i.deletePart(s, part);
              Navigator.pop(d);
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.redAccent)),
          ),
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            var t = (int.tryParse(min.text) ?? 0) * 60 + (int.tryParse(sec.text) ?? 0);
            final dur = Store.i.player.duration?.inSeconds;
            if (dur != null && t > dur) t = dur;
            final label = name.text.trim().isEmpty ? 'Best Part ${s.parts.length + 1}' : name.text.trim();
            Store.i.savePart(s, part, label, t);
            Navigator.pop(d);
          },
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.i,
      builder: (ctx, _) {
        final st = Store.i;
        final s = st.current;
        if (s == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => openPlayer(ctx),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
            decoration: BoxDecoration(
              color: const Color(0xFF211C45),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withAlpha(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Cover(s, size: 46, radius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(s.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  StreamBuilder<bool>(
                    stream: st.player.playingStream,
                    initialData: false,
                    builder: (_, snap) => IconButton(
                      onPressed: st.toggle,
                      icon: Icon(snap.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30),
                    ),
                  ),
                  IconButton(onPressed: st.next, icon: const Icon(Icons.skip_next_rounded, size: 28)),
                ]),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: StreamBuilder<Duration>(
                    stream: st.player.positionStream,
                    builder: (_, snap) {
                      final d = st.player.duration?.inMilliseconds ?? 0;
                      final v = d > 0 ? ((snap.data?.inMilliseconds ?? 0) / d).clamp(0.0, 1.0).toDouble() : 0.0;
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: v,
                          minHeight: 3,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation(kAccent),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SeekBar extends StatefulWidget {
  const SeekBar({super.key});

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? drag;

  @override
  Widget build(BuildContext context) {
    final pl = Store.i.player;
    return StreamBuilder<Duration?>(
      stream: pl.durationStream,
      builder: (_, ds) {
        final dur = ds.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: pl.positionStream,
          builder: (_, ps) {
            final pos = ps.data ?? Duration.zero;
            final max = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
            final v = (drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max).toDouble();
            return Column(children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 5,
                  activeTrackColor: kAccent,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayColor: kAccent.withAlpha(50),
                ),
                child: Slider(
                  value: v,
                  max: max,
                  onChanged: dur.inMilliseconds > 0 ? (x) => setState(() => drag = x) : null,
                  onChangeEnd: (x) {
                    pl.seek(Duration(milliseconds: x.round()));
                    setState(() => drag = null);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(fmt(Duration(milliseconds: v.round())), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  Text(fmt(dur), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ]),
              ),
            ]);
          },
        );
      },
    );
  }
}

class PartTile extends StatelessWidget {
  const PartTile({super.key, required this.song, required this.width, this.part});
  final Song song;
  final BestPart? part;
  final double width;

  @override
  Widget build(BuildContext context) {
    final add = part == null;
    return SizedBox(
      width: width,
      height: 112,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: add
                ? null
                : LinearGradient(
                    colors: [kAccent.withAlpha(100), kPink.withAlpha(70)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: add ? Colors.white.withAlpha(10) : null,
            border: Border.all(color: Colors.white.withAlpha(add ? 45 : 30)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: add ? () => partDialog(context, song) : () => Store.i.jumpTo(part!),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: add
                  ? const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_circle_outline_rounded, size: 28, color: Colors.white70),
                        SizedBox(height: 6),
                        Text('Ajouter', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                      ]),
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withAlpha(35)),
                          child: const Icon(Icons.play_arrow_rounded, size: 20),
                        ),
                        const Spacer(),
                        InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => partDialog(context, song, part: part),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.edit_rounded, size: 18, color: Colors.white70),
                          ),
                        ),
                      ]),
                      const Spacer(),
                      Text(
                        fmt(Duration(seconds: part!.seconds)),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        part!.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  Widget _btn(IconData icon, VoidCallback f, {double size = 30}) =>
      IconButton(iconSize: size, onPressed: f, icon: Icon(icon));

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final cw = (w - 72).clamp(200.0, 340.0).toDouble();
    final tw = (w - 32 - 12) / 2;
    return Scaffold(
      body: ListenableBuilder(
        listenable: Store.i,
        builder: (context, _) {
          final st = Store.i;
          final s = st.current;
          if (s == null) return const SizedBox.shrink();
          return Backdrop(
            tint: paletteFor(s.title).first.withAlpha(120),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                child: Column(children: [
                  Row(children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 34),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text('EN LECTURE',
                            style: TextStyle(letterSpacing: 2, fontSize: 12, color: Colors.white60, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    IconButton(
                      onPressed: () => addToPlaylistSheet(context, [s]),
                      icon: const Icon(Icons.playlist_add_rounded, size: 28),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(color: paletteFor(s.title).first.withAlpha(110), blurRadius: 50, offset: const Offset(0, 20)),
                      ],
                    ),
                    child: Stack(children: [
                      Cover(s, size: cw, radius: 32),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Material(
                          color: Colors.black.withAlpha(140),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => st.pickCover(s),
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(Icons.add_photo_alternate_rounded, size: 22),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 26),
                  Row(children: [
                    const SizedBox(width: 48),
                    Expanded(
                      child: Text(
                        s.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.2),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        final n = await askText(context, 'Modifier le nom', initial: s.title);
                        if (n != null) st.rename(s, n);
                      },
                      icon: const Icon(Icons.edit_rounded, size: 20, color: Colors.white70),
                    ),
                  ]),
                  if (st.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(st.error!,
                          textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                    ),
                  const SizedBox(height: 10),
                  const SeekBar(),
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    _btn(Icons.skip_previous_rounded, st.previous, size: 38),
                    _btn(st.step == 5 ? Icons.replay_5_rounded : Icons.replay_10_rounded, () => st.skip(-st.step)),
                    StreamBuilder<PlayerState>(
                      stream: st.player.playerStateStream,
                      builder: (_, snap) {
                        final ps = snap.data;
                        final playing = ps?.playing ?? false;
                        final busy = ps?.processingState == ProcessingState.loading ||
                            ps?.processingState == ProcessingState.buffering;
                        return Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                                colors: [kAccent, kPink], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            boxShadow: [BoxShadow(color: kPink.withAlpha(100), blurRadius: 28, offset: const Offset(0, 10))],
                          ),
                          child: busy
                              ? const Padding(
                                  padding: EdgeInsets.all(26),
                                  child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                                )
                              : IconButton(
                                  iconSize: 46,
                                  color: Colors.white,
                                  onPressed: st.toggle,
                                  icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                ),
                        );
                      },
                    ),
                    _btn(st.step == 5 ? Icons.forward_5_rounded : Icons.forward_10_rounded, () => st.skip(st.step)),
                    _btn(Icons.skip_next_rounded, st.next, size: 38),
                  ]),
                  const SizedBox(height: 18),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Material(
                      color: st.repeatOne ? kAccent.withAlpha(70) : Colors.white.withAlpha(14),
                      shape: StadiumBorder(side: BorderSide(color: st.repeatOne ? kAccent : Colors.white24)),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: st.toggleRepeat,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(st.repeatOne ? Icons.repeat_one_rounded : Icons.playlist_play_rounded, size: 20),
                            const SizedBox(width: 8),
                            Text(st.repeatOne ? 'Boucle' : 'Liste', style: const TextStyle(fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 5, label: Text('5 s')),
                        ButtonSegment(value: 10, label: Text('10 s')),
                      ],
                      selected: {st.step},
                      onSelectionChanged: (v) => st.setStep(v.first),
                      style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                    ),
                  ]),
                  const SizedBox(height: 32),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_rounded, color: Color(0xFFFBBF24)),
                      const SizedBox(width: 8),
                      const Text('Best Parts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 10),
                      Text('${s.parts.length}', style: const TextStyle(color: Colors.white54, fontSize: 16)),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 12, runSpacing: 12, children: [
                      for (final part in s.parts) PartTile(song: s, part: part, width: tw),
                      PartTile(song: s, width: tw),
                    ]),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}
