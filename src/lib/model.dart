import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SlideLayout { title, bullets, quote }

class DeckTheme {
  const DeckTheme(this.name, this.gradient, this.accent, {this.dark = true});
  final String name;
  final List<Color> gradient;
  final Color accent;
  final bool dark;
  Color get fg => dark ? Colors.white : const Color(0xFF1C1917);
}

const kThemes = <DeckTheme>[
  DeckTheme('Midnight', [Color(0xFF0F172A), Color(0xFF312E81)], Color(0xFF93C5FD)),
  DeckTheme('Coral', [Color(0xFF4C0519), Color(0xFFE11D48)], Color(0xFFFDE68A)),
  DeckTheme('Lagoon', [Color(0xFF042F2E), Color(0xFF0E7490)], Color(0xFF5EEAD4)),
  DeckTheme('Moss', [Color(0xFF14290F), Color(0xFF3F6212)], Color(0xFFD9F99D)),
  DeckTheme('Paper', [Color(0xFFFAFAF9), Color(0xFFE7E5E4)], Color(0xFFEA580C), dark: false),
  DeckTheme('Graphite', [Color(0xFF09090B), Color(0xFF3F3F46)], Color(0xFFF4F4F5)),
];

int _idCounter = 0;
String newId() => '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

class Slide {
  const Slide({
    required this.id,
    this.title = '',
    this.body = '',
    this.layout = SlideLayout.title,
    this.theme = 0,
  });

  final String id;
  final String title;
  final String body;
  final SlideLayout layout;
  final int theme;

  Slide copyWith({
    String? id,
    String? title,
    String? body,
    SlideLayout? layout,
    int? theme,
  }) =>
      Slide(
        id: id ?? this.id,
        title: title ?? this.title,
        body: body ?? this.body,
        layout: layout ?? this.layout,
        theme: theme ?? this.theme,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'layout': layout.name,
        'theme': theme,
      };

  factory Slide.fromJson(Map<String, dynamic> j) => Slide(
        id: j['id'] as String? ?? newId(),
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        layout: SlideLayout.values.asNameMap()[j['layout']] ?? SlideLayout.title,
        theme: (j['theme'] as int? ?? 0).clamp(0, kThemes.length - 1).toInt(),
      );
}

class Deck extends ChangeNotifier {
  static const _key = 'deck.v1';

  List<Slide> slides = [];
  bool loaded = false;

  /// Markdown file this deck was opened from / last saved to, if any.
  String? filePath;

  /// True when the deck has edits that are not in [filePath] yet.
  bool dirty = false;

  Timer? _debounce;

  String get name => filePath == null ? 'Untitled' : stripExtension(baseName(filePath!));

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final data = jsonDecode(raw);
        final list = data is List ? data : (data as Map)['slides'] as List;
        slides = list.map((e) => Slide.fromJson(e as Map<String, dynamic>)).toList();
        if (data is Map) {
          filePath = data['path'] as String?;
          dirty = data['dirty'] as bool? ?? false;
        }
      }
    } catch (_) {
      // Fall through to the starter deck.
    }
    if (slides.isEmpty) slides = _starter();
    loaded = true;
    notifyListeners();
  }

  List<Slide> _starter() => [
        Slide(
          id: newId(),
          title: 'Your first deck',
          body: 'Write slides on the left, present them full screen',
          layout: SlideLayout.title,
          theme: 0,
        ),
        Slide(
          id: newId(),
          title: 'Three layouts',
          body: 'Title slides for openers\nBullet slides, one line per point\nQuote slides for a single big idea',
          layout: SlideLayout.bullets,
          theme: 2,
        ),
        Slide(
          id: newId(),
          title: 'While presenting',
          body: 'Arrow keys, space or a tap to move\nEsc closes the presentation\nControls fade out after a moment',
          layout: SlideLayout.bullets,
          theme: 5,
        ),
        Slide(
          id: newId(),
          title: 'Anyone who ships it',
          body: 'Make it simple enough that the next change is obvious.',
          layout: SlideLayout.quote,
          theme: 1,
        ),
      ];

  Slide? byId(String id) {
    for (final s in slides) {
      if (s.id == id) return s;
    }
    return null;
  }

  int indexOf(String id) => slides.indexWhere((s) => s.id == id);

  Slide add({int? after}) {
    final at = (after ?? slides.length - 1) + 1;
    final prev = at > 0 && at - 1 < slides.length ? slides[at - 1] : null;
    final s = Slide(
      id: newId(),
      title: 'New slide',
      layout: SlideLayout.bullets,
      theme: prev?.theme ?? 0,
    );
    slides.insert(at.clamp(0, slides.length).toInt(), s);
    _changed();
    return s;
  }

  Slide? duplicate(String id) {
    final i = indexOf(id);
    if (i < 0) return null;
    final copy = slides[i].copyWith(id: newId());
    slides.insert(i + 1, copy);
    _changed();
    return copy;
  }

  void remove(String id) {
    slides.removeWhere((s) => s.id == id);
    _changed();
  }

  void move(int from, int to) {
    final s = slides.removeAt(from);
    slides.insert(to, s);
    _changed();
  }

  void update(String id, {String? title, String? body, SlideLayout? layout, int? theme}) {
    final i = indexOf(id);
    if (i < 0) return;
    slides[i] = slides[i].copyWith(title: title, body: body, layout: layout, theme: theme);
    _changed();
  }

  /// Replaces the whole deck, e.g. after opening a file. Not dirty afterwards.
  void replaceAll(List<Slide> next, {String? path}) {
    slides = next;
    filePath = path;
    dirty = false;
    notifyListeners();
    _persist();
  }

  void newDeck() => replaceAll([
        Slide(id: newId(), title: 'Untitled slide', layout: SlideLayout.title),
      ]);

  void markSaved(String path) {
    filePath = path;
    dirty = false;
    notifyListeners();
    _persist();
  }

  void _changed() {
    dirty = true;
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _save);
  }

  // Working copy kept in app storage so nothing is lost between launches.
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'slides': slides.map((s) => s.toJson()).toList(),
          'path': filePath,
          'dirty': dirty,
        }),
      );
    } catch (_) {}
  }

  void _persist() {
    _debounce?.cancel();
    _save();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}



// ─────────────────────────────────────────────────────────────────────────
// Path helpers (no dependency on package:path)
// ─────────────────────────────────────────────────────────────────────────

String baseName(String path) => path.split(RegExp(r'[\\/]')).last;

String stripExtension(String file) {
  final i = file.lastIndexOf('.');
  return i > 0 ? file.substring(0, i) : file;
}
