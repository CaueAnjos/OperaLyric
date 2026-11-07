import 'dart:io';

import 'model.dart';

/// Reads and writes decks as plain Markdown.
///
/// One file is one deck. Slides are separated by a line containing only `---`.
/// Each slide may start with a directive comment:
///
///     <!-- layout: bullets; theme: Lagoon -->
///     # Slide title
///
///     - first point
///     - second point
///
/// Without a directive the layout is inferred: `> text` is a quote, `- text`
/// is a bullet list, anything else is a title slide.
abstract final class MarkdownDeck {
  static final _separator = RegExp(r'^\s*---+\s*$');
  static final _directive = RegExp(r'^<!--(.*)-->$');
  static final _heading = RegExp(r'^#{1,6}\s+(.*)$');
  static final _bullet = RegExp(r'^\s*(?:[-*+]|\d+\.)\s+');
  static final _frontMatterLine = RegExp(r'^[\w-]+:(\s|$)');

  // ── Encode ─────────────────────────────────────────────────────────────

  static String encode(List<Slide> slides) {
    final out = StringBuffer();
    for (var i = 0; i < slides.length; i++) {
      if (i > 0) out.write('\n---\n\n');
      out.write(_encodeSlide(slides[i]));
    }
    out.write('\n');
    return out.toString();
  }

  static String _encodeSlide(Slide s) {
    final theme = kThemes[s.theme.clamp(0, kThemes.length - 1).toInt()];
    final lines = <String>['<!-- layout: ${s.layout.name}; theme: ${theme.name} -->'];
    final body = s.body.split('\n').map((l) => l.trimRight()).where((l) => l.isNotEmpty);

    switch (s.layout) {
      case SlideLayout.title:
        if (s.title.trim().isNotEmpty) lines.add('# ${s.title.trim()}');
        if (body.isNotEmpty) {
          lines.add('');
          lines.addAll(body);
        }
      case SlideLayout.bullets:
        if (s.title.trim().isNotEmpty) lines.add('# ${s.title.trim()}');
        if (body.isNotEmpty) {
          lines.add('');
          lines.addAll(body.map((l) => '- $l'));
        }
      case SlideLayout.quote:
        if (body.isNotEmpty) {
          lines.add('');
          lines.addAll(body.map((l) => '> $l'));
        }
        if (s.title.trim().isNotEmpty) {
          lines.add('');
          lines.add('\u2014 ${s.title.trim()}');
        }
    }
    return lines.join('\n');
  }

  // ── Decode ─────────────────────────────────────────────────────────────

  static List<Slide> decode(String text) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final chunks = <List<String>>[[]];
    for (final line in lines) {
      if (_separator.hasMatch(line)) {
        chunks.add([]);
      } else {
        chunks.last.add(line);
      }
    }

    // A file that opens with `---` key: value `---` has YAML front matter.
    // Skip it instead of turning it into a slide.
    final startsWithRule = lines.isNotEmpty && _separator.hasMatch(lines.first);
    if (startsWithRule && chunks.length > 2) {
      final meta = chunks[1].where((l) => l.trim().isNotEmpty).toList();
      if (meta.isNotEmpty && meta.every(_frontMatterLine.hasMatch)) chunks.removeAt(1);
    }

    final slides = <Slide>[];
    for (final chunk in chunks) {
      final slide = _decodeSlide(chunk);
      if (slide != null) slides.add(slide);
    }
    return slides;
  }

  static Slide? _decodeSlide(List<String> lines) {
    String? layoutName;
    String? themeName;
    var hasDirective = false;
    var title = '';
    final body = <String>[];

    for (final raw in lines) {
      final line = raw.trimRight();
      final d = _directive.firstMatch(line.trim());
      if (d != null) {
        hasDirective = true;
        for (final pair in d.group(1)!.split(RegExp(r'[;,]'))) {
          final i = pair.indexOf(':');
          if (i < 0) continue;
          final key = pair.substring(0, i).trim().toLowerCase();
          final value = pair.substring(i + 1).trim();
          if (key == 'layout') layoutName = value.toLowerCase();
          if (key == 'theme') themeName = value;
        }
        continue;
      }
      final h = _heading.firstMatch(line);
      if (h != null && title.isEmpty) {
        title = h.group(1)!.trim();
        continue;
      }
      body.add(line);
    }

    final content = body.where((l) => l.trim().isNotEmpty).toList();
    if (!hasDirective && title.isEmpty && content.isEmpty) return null;

    final layout = SlideLayout.values.asNameMap()[layoutName] ??
        (content.any((l) => l.trimLeft().startsWith('>'))
            ? SlideLayout.quote
            : content.any(_bullet.hasMatch)
                ? SlideLayout.bullets
                : SlideLayout.title);

    var text = '';
    switch (layout) {
      case SlideLayout.title:
        text = content.map((l) => l.trim()).join('\n');
      case SlideLayout.bullets:
        text = content.map((l) => l.replaceFirst(_bullet, '').trim()).join('\n');
      case SlideLayout.quote:
        final quote = <String>[];
        String? attribution;
        for (final l in content) {
          final t = l.trim();
          if (t.startsWith('\u2014') || t.startsWith('--')) {
            attribution = t.replaceFirst(RegExp(r'^(\u2014|--+)\s*'), '');
          } else {
            quote.add(t.replaceFirst(RegExp(r'^>\s?'), ''));
          }
        }
        text = quote.join('\n');
        title = attribution ?? title;
    }

    return Slide(
      id: newId(),
      title: title,
      body: text,
      layout: layout,
      theme: _themeIndex(themeName),
    );
  }

  static int _themeIndex(String? v) {
    if (v == null) return 0;
    final byName = kThemes.indexWhere((t) => t.name.toLowerCase() == v.toLowerCase());
    if (byName >= 0) return byName;
    final n = int.tryParse(v);
    return n == null ? 0 : n.clamp(0, kThemes.length - 1).toInt();
  }
}

// ─────────────────────────────────────────────────────────────────────────
// File helpers
// ─────────────────────────────────────────────────────────────────────────

/// Reads slides from a Markdown file. Throws if it has none.
Future<List<Slide>> readSlidesFile(String path) async {
  final slides = MarkdownDeck.decode(await File(path).readAsString());
  if (slides.isEmpty) throw FormatException('No slides found in ${baseName(path)}');
  return slides;
}

Future<void> openDeckFile(Deck deck, String path) async {
  deck.replaceAll(await readSlidesFile(path), path: path);
}

Future<void> saveDeckFile(Deck deck, String path) async {
  await File(path).writeAsString(MarkdownDeck.encode(deck.slides));
  deck.markSaved(path);
}
