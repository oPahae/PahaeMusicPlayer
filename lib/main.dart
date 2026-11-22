import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'download.dart';
import 'handler.dart';
import 'player.dart';
import 'store.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AudioService.init(
    builder: PlayerHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.pahae.music.playback',
      androidNotificationChannelName: 'PahaeMusic',
      androidNotificationIcon: 'drawable/ic_notification',
      androidNotificationOngoing: false,
      notificationColor: Color(0xFF8B5CF6),
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
    ),
  );
  Store.i.init();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PahaeMusic',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: kAccent, brightness: Brightness.dark),
        scaffoldBackgroundColor: kBg,
        dialogTheme: DialogThemeData(
          backgroundColor: kCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF2A2455),
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      home: const Home(),
    );
  }
}

Future<bool> deleteSongsFlow(BuildContext c, List<Song> list) async {
  final n = list.length;
  final yes = await confirm(
    c,
    n == 1
        ? 'Supprimer « ${list.first.title} » du téléphone ? Cette action est définitive.'
        : 'Supprimer $n musiques du téléphone ? Cette action est définitive.',
  );
  if (!yes) return false;
  final err = await Store.i.deleteSongs(list);
  if (c.mounted) {
    toast(c, err ?? (n == 1 ? 'Musique supprimée' : '$n musiques supprimées'));
  }
  return err == null;
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            Expanded(child: IndexedStack(index: tab, children: const [SongsTab(), PlaylistsTab(), DownloadTab()])),
            const MiniPlayer(),
          ]),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        backgroundColor: kCard,
        indicatorColor: kAccent.withAlpha(90),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music_rounded), label: 'Titres'),
          NavigationDestination(
              icon: Icon(Icons.queue_music_outlined), selectedIcon: Icon(Icons.queue_music_rounded), label: 'Playlists'),
          NavigationDestination(
              icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download_rounded), label: 'Télécharger'),
        ],
      ),
    );
  }
}

class Empty extends StatelessWidget {
  const Empty({super.key, required this.icon, required this.text, this.actions = const []});
  final IconData icon;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 15)),
          const SizedBox(height: 16),
          ...actions,
        ]),
      ),
    );
  }
}

class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.queue,
    required this.index,
    this.playlist,
    this.selecting = false,
    this.selected = false,
    this.onToggle,
  });
  final Song song;
  final List<Song> queue;
  final int index;
  final Playlist? playlist;
  final bool selecting;
  final bool selected;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final st = Store.i;
    final active = st.current?.path == song.path;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        tileColor: selected ? kAccent.withAlpha(55) : null,
        contentPadding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
        onTap: selecting
            ? onToggle
            : () {
                st.play(queue, index);
                openPlayer(context);
              },
        onLongPress: onToggle,
        leading: Stack(children: [
          Cover(song),
          if (selected)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ColoredBox(
                  color: kAccent.withAlpha(180),
                  child: const Icon(Icons.check_rounded, color: Colors.white),
                ),
              ),
            ),
        ]),
        title: Text(
          song.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w600, height: 1.25, color: active ? const Color(0xFFB794F6) : null),
        ),
        trailing: selecting
            ? Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? kAccent : Colors.white38,
                ),
              )
            : PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white60),
                onSelected: (v) async {
                  if (v == 'rename') {
                    final n = await askText(context, 'Modifier le nom', initial: song.title);
                    if (n != null) st.rename(song, n);
                  } else if (v == 'playlist') {
                    addToPlaylistSheet(context, [song]);
                  } else if (v == 'remove' && playlist != null) {
                    st.removeFromPlaylist(playlist!, song.path);
                  } else if (v == 'delete') {
                    deleteSongsFlow(context, [song]);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Text('Modifier le nom')),
                  const PopupMenuItem(value: 'playlist', child: Text('Ajouter à une playlist')),
                  if (playlist != null) const PopupMenuItem(value: 'remove', child: Text('Retirer de la playlist')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Supprimer du téléphone', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
      ),
    );
  }
}

class SongsTab extends StatefulWidget {
  const SongsTab({super.key});

  @override
  State<SongsTab> createState() => _SongsTabState();
}

class _SongsTabState extends State<SongsTab> {
  String q = '';
  final Set<String> sel = {};

  bool get selecting => sel.isNotEmpty;

  void toggle(Song s) => setState(() {
        if (!sel.remove(s.path)) sel.add(s.path);
      });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.i,
      builder: (context, _) {
        final st = Store.i;
        final list = st.songs.where((s) => s.title.toLowerCase().contains(q.toLowerCase())).toList();
        final chosen = st.songs.where((s) => sel.contains(s.path)).toList();
        Widget body;
        if (st.loading) {
          body = const Center(child: CircularProgressIndicator());
        } else if (st.denied) {
          body = Empty(
            icon: Icons.lock_outline_rounded,
            text: 'L’accès aux fichiers audio est nécessaire pour afficher votre musique.',
            actions: [
              FilledButton(onPressed: st.scan, child: const Text('Autoriser')),
              TextButton(onPressed: openAppSettings, child: const Text('Ouvrir les réglages')),
            ],
          );
        } else if (list.isEmpty) {
          body = const Empty(icon: Icons.music_off_rounded, text: 'Aucune musique trouvée.');
        } else {
          body = ListView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: list.length,
            itemBuilder: (_, i) => SongTile(
              song: list[i],
              queue: list,
              index: i,
              selecting: selecting,
              selected: sel.contains(list[i].path),
              onToggle: () => toggle(list[i]),
            ),
          );
        }
        final header = selecting
            ? Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                child: Row(children: [
                  IconButton(onPressed: () => setState(sel.clear), icon: const Icon(Icons.close_rounded)),
                  Expanded(
                    child: Text(
                      '${sel.length} sélectionnée${sel.length > 1 ? 's' : ''}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tout sélectionner',
                    onPressed: () => setState(() => sel.addAll(list.map((s) => s.path))),
                    icon: const Icon(Icons.select_all_rounded),
                  ),
                  IconButton(
                    tooltip: 'Ajouter à une playlist',
                    onPressed: () async {
                      await addToPlaylistSheet(context, chosen);
                      if (mounted) setState(sel.clear);
                    },
                    icon: const Icon(Icons.playlist_add_rounded),
                  ),
                  IconButton(
                    tooltip: 'Supprimer',
                    onPressed: () async {
                      final ok = await deleteSongsFlow(context, chosen);
                      if (ok && mounted) setState(sel.clear);
                    },
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  ),
                ]),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 4, 0),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Ma musique', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                      Text('${st.songs.length} titres', style: const TextStyle(color: Colors.white54)),
                    ]),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Trier',
                    icon: const Icon(Icons.sort_rounded),
                    initialValue: st.sort,
                    onSelected: st.setSort,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'date_desc', child: Text('Date : plus récent')),
                      PopupMenuItem(value: 'date_asc', child: Text('Date : plus ancien')),
                      PopupMenuItem(value: 'name_asc', child: Text('Nom : A → Z')),
                      PopupMenuItem(value: 'name_desc', child: Text('Nom : Z → A')),
                    ],
                  ),
                  IconButton(onPressed: st.scan, icon: const Icon(Icons.refresh_rounded)),
                ]),
              );
        return PopScope(
          canPop: !selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(sel.clear);
          },
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            header,
            if (st.setupMissing)
              Container(
                margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(40),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Text(
                  'Installation incomplète : lancez « dart tool/setup.dart » dans le dossier du projet, puis réinstallez l’application.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: TextField(
                onChanged: (v) => setState(() => q = v),
                decoration: InputDecoration(
                  hintText: 'Rechercher un titre',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: kCard,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                ),
              ),
            ),
            Expanded(child: body),
          ]),
        );
      },
    );
  }
}

class PlaylistsTab extends StatelessWidget {
  const PlaylistsTab({super.key});

  Future<void> _create(BuildContext c) async {
    final n = await askText(c, 'Nouvelle playlist', hint: 'Nom de la playlist');
    if (n != null && n.trim().isNotEmpty) Store.i.createPlaylist(n);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.i,
      builder: (context, _) {
        final st = Store.i;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
            child: Row(children: [
              const Expanded(child: Text('Playlists', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800))),
              IconButton.filled(
                onPressed: () => _create(context),
                style: IconButton.styleFrom(backgroundColor: kAccent),
                icon: const Icon(Icons.add_rounded),
              ),
            ]),
          ),
          Expanded(
            child: st.playlists.isEmpty
                ? Empty(
                    icon: Icons.queue_music_rounded,
                    text: 'Créez votre première playlist pour organiser votre musique.',
                    actions: [FilledButton(onPressed: () => _create(context), child: const Text('Créer une playlist'))],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: st.playlists.length,
                    itemBuilder: (_, i) {
                      final pl = st.playlists[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        child: Material(
                          color: kCard,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => Navigator.of(context)
                                .push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(pl))),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                              child: Row(children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    gradient: gradientFor(pl.name),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(Icons.queue_music_rounded, color: Colors.white),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(pl.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                    Text('${pl.paths.length} titres', style: const TextStyle(color: Colors.white54)),
                                  ]),
                                ),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white60),
                                  onSelected: (v) async {
                                    if (v == 'rename') {
                                      final n = await askText(context, 'Renommer la playlist', initial: pl.name);
                                      if (n != null) st.renamePlaylist(pl, n);
                                    } else if (await confirm(context, 'Supprimer la playlist « ${pl.name} » ?')) {
                                      st.deletePlaylist(pl);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'rename', child: Text('Renommer')),
                                    PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                                  ],
                                ),
                              ]),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ]);
      },
    );
  }
}

class PlaylistPage extends StatelessWidget {
  const PlaylistPage(this.playlist, {super.key});
  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: Column(children: [
            Expanded(
              child: ListenableBuilder(
                listenable: Store.i,
                builder: (context, _) {
                  final list = Store.i.songsOf(playlist);
                  return Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
                      child: Row(children: [
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
                        Expanded(
                          child: Text(playlist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                        ),
                        FilledButton.icon(
                          onPressed: list.isEmpty
                              ? null
                              : () {
                                  Store.i.play(list, 0);
                                  openPlayer(context);
                                },
                          style: FilledButton.styleFrom(backgroundColor: kAccent),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Lire'),
                        ),
                      ]),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? const Empty(
                              icon: Icons.library_add_rounded,
                              text: 'Cette playlist est vide. Ajoutez des titres depuis le menu ⋮ d’une musique.')
                          : ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (_, i) =>
                                  SongTile(song: list[i], queue: list, index: i, playlist: playlist),
                            ),
                    ),
                  ]);
                },
              ),
            ),
            const MiniPlayer(),
          ]),
        ),
      ),
    );
  }
}
