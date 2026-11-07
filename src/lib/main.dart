import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop.dart';
import 'markdown.dart';
import 'model.dart';
import 'playlist.dart';
import 'present.dart';
import 'slide_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isDesktop) await windowManager.ensureInitialized();
  runApp(const OperaLyricApp());
}

class OperaLyricApp extends StatelessWidget {
  const OperaLyricApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C83FF),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Slides',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF111114),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final deck = Deck();
  final playlist = Playlist();
  String? _sel;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    playlist.load();
    await deck.load();
    // Pick up outside edits to a deck that has no unsaved changes here.
    final path = deck.filePath;
    if (path != null && !deck.dirty) {
      try {
        await openDeckFile(deck, path);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    deck.dispose();
    playlist.dispose();
    super.dispose();
  }

  int get _selIndex {
    final i = _sel == null ? -1 : deck.indexOf(_sel!);
    return i < 0 ? 0 : i;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Slides ─────────────────────────────────────────────────────────────

  void _openSlide(String id, bool wide) {
    setState(() => _sel = id);
    if (!wide) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EditorScreen(deck: deck, slideId: id),
      ));
    }
  }

  void _add(bool wide) {
    final s = deck.add(after: deck.slides.isEmpty ? null : _selIndex);
    _openSlide(s.id, wide);
  }

  void _delete(String id) {
    final i = deck.indexOf(id);
    deck.remove(id);
    setState(() {
      _sel = deck.slides.isEmpty
          ? null
          : deck.slides[i.clamp(0, deck.slides.length - 1).toInt()].id;
    });
  }

  void _duplicate(String id) {
    final copy = deck.duplicate(id);
    if (copy != null) setState(() => _sel = copy.id);
  }

  // ── Files ──────────────────────────────────────────────────────────────

  Future<bool> _confirmDiscard() async {
    if (!deck.dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: Text(
            '\u201C${deck.name}\u201D has changes that are not saved to a file.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _newDeck() async {
    if (!await _confirmDiscard()) return;
    deck.newDeck();
    setState(() => _sel = null);
  }

  Future<void> _openFile() async {
    if (!await _confirmDiscard()) return;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open Markdown deck',
      type: FileType.custom,
      allowedExtensions: const ['md', 'markdown'],
    );
    final path = result?.files.first.path;
    if (path == null) return;
    try {
      await openDeckFile(deck, path);
      setState(() => _sel = null);
    } catch (e) {
      _snack('Could not open ${baseName(path)}: $e');
    }
  }

  Future<void> _saveFile({bool saveAs = false}) async {
    var path = deck.filePath;
    if (saveAs || path == null) {
      path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save deck as Markdown',
        fileName: '${deck.name}.md',
        type: FileType.custom,
        allowedExtensions: const ['md'],
      );
      if (path == null) return;
      final lower = path.toLowerCase();
      if (!lower.endsWith('.md') && !lower.endsWith('.markdown'))
        path = '$path.md';
    }
    try {
      await saveDeckFile(deck, path);
      _snack('Saved ${baseName(path)}');
    } catch (e) {
      _snack('Could not save ${baseName(path)}: $e');
    }
  }

  void _openPlaylist() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlaylistPage(playlist: playlist),
    ));
  }

  void _present(int from) {
    if (deck.slides.isEmpty) return;
    Navigator.of(context)
        .push(presentRoute(slides: List.of(deck.slides), start: from));
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: deck,
      builder: (context, _) {
        if (!deck.loaded) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final hasSlides = deck.slides.isNotEmpty;
        final currentId = hasSlides ? deck.slides[_selIndex].id : null;
        final cs = Theme.of(context).colorScheme;

        final list = SlideList(
          deck: deck,
          selectedId: wide ? currentId : null,
          onSelect: (id) => _openSlide(id, wide),
          onAdd: () => _add(wide),
          onDelete: _delete,
          onDuplicate: _duplicate,
        );

        // Ctrl on Linux/Windows, Cmd on macOS.
        Map<ShortcutActivator, VoidCallback> both(
          LogicalKeyboardKey key,
          VoidCallback cb, {
          bool shift = false,
        }) =>
            {
              SingleActivator(key, control: true, shift: shift): cb,
              SingleActivator(key, meta: true, shift: shift): cb,
            };

        return CallbackShortcuts(
          bindings: {
            ...both(LogicalKeyboardKey.keyO, _openFile),
            ...both(LogicalKeyboardKey.keyS, _saveFile),
            ...both(LogicalKeyboardKey.keyS, () => _saveFile(saveAs: true),
                shift: true),
            ...both(LogicalKeyboardKey.keyN, _newDeck),
            const SingleActivator(LogicalKeyboardKey.f5): () =>
                _present(_selIndex),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(
                titleSpacing: 20,
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient:
                            LinearGradient(colors: [cs.primary, cs.tertiary]),
                      ),
                      child: Icon(Icons.slideshow_rounded,
                          size: 18, color: cs.onPrimary),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        '${deck.name}${deck.dirty ? ' \u2022' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                actions: [
                  PopupMenuButton<String>(
                    tooltip: 'File',
                    icon: const Icon(Icons.folder_open_rounded),
                    onSelected: (v) {
                      switch (v) {
                        case 'new':
                          _newDeck();
                        case 'open':
                          _openFile();
                        case 'save':
                          _saveFile();
                        case 'saveAs':
                          _saveFile(saveAs: true);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'new', child: Text('New deck')),
                      PopupMenuItem(value: 'open', child: Text('Open\u2026')),
                      PopupMenuItem(value: 'save', child: Text('Save')),
                      PopupMenuItem(
                          value: 'saveAs', child: Text('Save as\u2026')),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Playlist',
                    icon: const Icon(Icons.playlist_play_rounded),
                    onPressed: _openPlaylist,
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: FilledButton.icon(
                      onPressed: hasSlides ? () => _present(_selIndex) : null,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Present'),
                    ),
                  ),
                ],
              ),
              body: wide
                  ? Row(
                      children: [
                        SizedBox(width: 330, child: list),
                        VerticalDivider(
                          width: 1,
                          color: cs.outlineVariant.withValues(alpha: 0.4),
                        ),
                        Expanded(
                          child: currentId == null
                              ? const _EmptyEditor()
                              : EditorPane(
                                  key: ValueKey(currentId),
                                  deck: deck,
                                  slideId: currentId,
                                ),
                        ),
                      ],
                    )
                  : list,
            ),
          ),
        );
      },
    );
  }
}

class _EmptyEditor extends StatelessWidget {
  const _EmptyEditor();
  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Add a slide to start editing.'));
}

class SlideList extends StatelessWidget {
  const SlideList({
    super.key,
    required this.deck,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
    required this.onDuplicate,
  });

  final Deck deck;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onDuplicate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = deck.slides.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  n == 1 ? '1 slide' : '$n slides',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add slide'),
              ),
            ],
          ),
        ),
        Expanded(
          child: n == 0
              ? const Center(child: Text('No slides yet. Add one to begin.'))
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: n,
                  onReorder: (oldI, newI) {
                    if (newI > oldI) newI -= 1;
                    deck.move(oldI, newI);
                  },
                  itemBuilder: (context, i) {
                    final s = deck.slides[i];
                    final selected = s.id == selectedId;
                    return Padding(
                      key: ValueKey(s.id),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: selected
                            ? cs.primaryContainer.withValues(alpha: 0.3)
                            : Colors.transparent,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: selected
                                ? cs.primary
                                : cs.outlineVariant.withValues(alpha: 0.5),
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: () => onSelect(s.id),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
                            child: Row(
                              children: [
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(Icons.drag_indicator_rounded,
                                        size: 20),
                                  ),
                                ),
                                SizedBox(
                                  width: 22,
                                  child: Text(
                                    '${i + 1}',
                                    textAlign: TextAlign.center,
                                    style:
                                        Theme.of(context).textTheme.labelMedium,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SlideView(s),
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert_rounded,
                                      size: 20),
                                  onSelected: (v) {
                                    if (v == 'dup') onDuplicate(s.id);
                                    if (v == 'del') onDelete(s.id);
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                        value: 'dup', child: Text('Duplicate')),
                                    PopupMenuItem(
                                        value: 'del', child: Text('Delete')),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Full-screen editor used on narrow (phone) layouts.
class EditorScreen extends StatelessWidget {
  const EditorScreen({super.key, required this.deck, required this.slideId});
  final Deck deck;
  final String slideId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit slide'),
        actions: [
          IconButton(
            tooltip: 'Delete slide',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () {
              deck.remove(slideId);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: EditorPane(deck: deck, slideId: slideId),
    );
  }
}

class EditorPane extends StatefulWidget {
  const EditorPane({super.key, required this.deck, required this.slideId});
  final Deck deck;
  final String slideId;

  @override
  State<EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<EditorPane> {
  late final TextEditingController _title;
  late final TextEditingController _body;

  @override
  void initState() {
    super.initState();
    final s = widget.deck.byId(widget.slideId);
    _title = TextEditingController(text: s?.title ?? '');
    _body = TextEditingController(text: s?.body ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.deck,
      builder: (context, _) {
        final slide = widget.deck.byId(widget.slideId);
        if (slide == null) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        final id = slide.id;

        final titleLabel =
            slide.layout == SlideLayout.quote ? 'Attribution' : 'Title';
        final bodyLabel = switch (slide.layout) {
          SlideLayout.title => 'Subtitle',
          SlideLayout.bullets => 'Bullets',
          SlideLayout.quote => 'Quote',
        };
        final bodyHelp =
            slide.layout == SlideLayout.bullets ? 'One bullet per line' : null;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 40,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SlideView(slide),
                  ),
                ),
                const SizedBox(height: 28),
                Text('Layout', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 10),
                SegmentedButton<SlideLayout>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: SlideLayout.title,
                      icon: Icon(Icons.title_rounded),
                      label: Text('Title'),
                    ),
                    ButtonSegment(
                      value: SlideLayout.bullets,
                      icon: Icon(Icons.format_list_bulleted_rounded),
                      label: Text('Bullets'),
                    ),
                    ButtonSegment(
                      value: SlideLayout.quote,
                      icon: Icon(Icons.format_quote_rounded),
                      label: Text('Quote'),
                    ),
                  ],
                  selected: {slide.layout},
                  onSelectionChanged: (s) =>
                      widget.deck.update(id, layout: s.first),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _title,
                  decoration: InputDecoration(
                    labelText: titleLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onChanged: (v) => widget.deck.update(id, title: v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _body,
                  minLines: 4,
                  maxLines: 10,
                  decoration: InputDecoration(
                    labelText: bodyLabel,
                    helperText: bodyHelp,
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onChanged: (v) => widget.deck.update(id, body: v),
                ),
                const SizedBox(height: 24),
                Text('Theme', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < kThemes.length; i++)
                      Tooltip(
                        message: kThemes[i].name,
                        child: GestureDetector(
                          onTap: () => widget.deck.update(id, theme: i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: kThemes[i].gradient,
                              ),
                              border: Border.all(
                                color: slide.theme == i
                                    ? cs.primary
                                    : cs.outlineVariant.withValues(alpha: 0.6),
                                width: slide.theme == i ? 3 : 1,
                              ),
                            ),
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: Container(
                                width: 14,
                                height: 14,
                                margin: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: kThemes[i].accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
