import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'markdown.dart';
import 'model.dart';
import 'present.dart';

/// An ordered list of Markdown files that are presented back to back.
class Playlist extends ChangeNotifier {
  static const _key = 'playlist.v1';

  List<String> paths = [];

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      paths = prefs.getStringList(_key) ?? [];
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, paths);
    } catch (_) {}
  }

  void add(Iterable<String> more) {
    paths = [...paths, ...more];
    notifyListeners();
    _save();
  }

  void removeAt(int i) {
    paths = [...paths]..removeAt(i);
    notifyListeners();
    _save();
  }

  void move(int from, int to) {
    final next = [...paths];
    next.insert(to, next.removeAt(from));
    paths = next;
    notifyListeners();
    _save();
  }

  void clear() {
    paths = [];
    notifyListeners();
    _save();
  }
}

class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key, required this.playlist});
  final Playlist playlist;

  Future<void> _addFiles() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Add Markdown decks to the playlist',
      type: FileType.custom,
      allowedExtensions: const ['md', 'markdown'],
      allowMultiple: true,
    );
    if (result == null) return;
    playlist.add(result.files.map((f) => f.path).whereType<String>());
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _present(BuildContext context) async {
    final slides = <Slide>[];
    final sources = <String>[];
    final skipped = <String>[];

    for (final path in playlist.paths) {
      try {
        final s = await readSlidesFile(path);
        slides.addAll(s);
        sources.addAll(List.filled(s.length, stripExtension(baseName(path))));
      } catch (_) {
        skipped.add(baseName(path));
      }
    }
    if (!context.mounted) return;
    if (slides.isEmpty) {
      _snack(context, 'None of the files could be read, so there is nothing to present.');
      return;
    }
    await Navigator.of(context).push(presentRoute(slides: slides, sources: sources));
    if (context.mounted && skipped.isNotEmpty) {
      _snack(context, 'Skipped unreadable files: ${skipped.join(', ')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: playlist,
      builder: (context, _) {
        final paths = playlist.paths;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Playlist'),
            actions: [
              if (paths.isNotEmpty)
                IconButton(
                  tooltip: 'Clear playlist',
                  icon: const Icon(Icons.clear_all_rounded),
                  onPressed: playlist.clear,
                ),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: FilledButton.tonalIcon(
                  onPressed: _addFiles,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add files'),
                ),
              ),
            ],
          ),
          body: paths.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Add Markdown files and they play in this order.\nDrag to reorder.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: paths.length,
                  onReorder: (o, n) {
                    if (n > o) n -= 1;
                    playlist.move(o, n);
                  },
                  itemBuilder: (context, i) {
                    final path = paths[i];
                    final exists = File(path).existsSync();
                    return Padding(
                      key: ValueKey('$i-$path'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          leading: ReorderableDragStartListener(
                            index: i,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.drag_indicator_rounded),
                                const SizedBox(width: 8),
                                Text('${i + 1}', style: Theme.of(context).textTheme.labelLarge),
                              ],
                            ),
                          ),
                          title: Text(
                            stripExtension(baseName(path)),
                            style: TextStyle(color: exists ? null : cs.error),
                          ),
                          subtitle: Text(
                            exists ? path : 'File not found: $path',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => playlist.removeAt(i),
                          ),
                        ),
                      ),
                    );
                  },
                ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: paths.isEmpty ? null : () => _present(context),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  paths.length == 1 ? 'Present 1 file' : 'Present ${paths.length} files',
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
