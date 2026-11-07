import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'desktop.dart';
import 'model.dart';
import 'slide_view.dart';

/// Route that fades into the presenter.
Route<void> presentRoute({
  required List<Slide> slides,
  List<String>? sources,
  int start = 0,
}) {
  return PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) => PresentPage(slides: slides, sources: sources, start: start),
    transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
  );
}

class PresentPage extends StatefulWidget {
  const PresentPage({super.key, required this.slides, this.sources, this.start = 0});
  final List<Slide> slides;

  /// Optional label per slide (the file it came from), shown in the controls.
  final List<String>? sources;
  final int start;

  @override
  State<PresentPage> createState() => _PresentPageState();
}

class _PresentPageState extends State<PresentPage> {
  late final PageController _pc;
  late int _i;
  bool _ui = true;
  late bool _full;
  Timer? _hide;

  int get _n => widget.slides.length;

  @override
  void initState() {
    super.initState();
    _i = widget.start.clamp(0, _n - 1).toInt();
    _pc = PageController(initialPage: _i);
    _full = isDesktop;
    if (isDesktop) {
      AppWindow.enterFullscreen();
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _poke();
  }

  @override
  void dispose() {
    _hide?.cancel();
    _pc.dispose();
    if (isDesktop) {
      AppWindow.restore();
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _poke() {
    if (!_ui) setState(() => _ui = true);
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _ui = false);
    });
  }

  void _goTo(int target) {
    final t = target.clamp(0, _n - 1).toInt();
    if (t == _i) return;
    _pc.animateToPage(
      t,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _toggleFullscreen() async {
    final now = await AppWindow.toggle();
    if (mounted) setState(() => _full = now);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.pageDown ||
        k == LogicalKeyboardKey.enter) {
      _goTo(_i + 1);
    } else if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.pageUp ||
        k == LogicalKeyboardKey.backspace) {
      _goTo(_i - 1);
    } else if (k == LogicalKeyboardKey.home) {
      _goTo(0);
    } else if (k == LogicalKeyboardKey.end) {
      _goTo(_n - 1);
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
    } else if (k == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
    } else {
      return KeyEventResult.ignored;
    }
    _poke();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: _ui ? MouseCursor.defer : SystemMouseCursors.none,
          onHover: (_) => _poke(),
          child: Stack(
            children: [
              GestureDetector(
                onTapUp: (d) {
                  final width = MediaQuery.sizeOf(context).width;
                  _goTo(d.localPosition.dx > width / 2 ? _i + 1 : _i - 1);
                  _poke();
                },
                child: PageView.builder(
                  controller: _pc,
                  itemCount: _n,
                  onPageChanged: (i) => setState(() => _i = i),
                  itemBuilder: (_, i) => Center(child: SlideView(widget.slides[i])),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  opacity: _ui ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: IgnorePointer(ignoring: !_ui, child: _controls(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final sources = widget.sources;
    final source = sources != null && _i < sources.length ? sources[_i] : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xCC000000)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_i + 1) / _n,
                minHeight: 4,
                backgroundColor: Colors.white24,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Exit (Esc)',
                        color: Colors.white,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      if (source != null)
                        Flexible(
                          child: Text(
                            source,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Previous',
                  color: Colors.white,
                  icon: const Icon(Icons.chevron_left_rounded, size: 30),
                  onPressed: _i > 0 ? () => _goTo(_i - 1) : null,
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    '${_i + 1} / $_n',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Next',
                  color: Colors.white,
                  icon: const Icon(Icons.chevron_right_rounded, size: 30),
                  onPressed: _i < _n - 1 ? () => _goTo(_i + 1) : null,
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: isDesktop
                        ? IconButton(
                            tooltip: _full ? 'Exit fullscreen (F)' : 'Fullscreen (F)',
                            color: Colors.white,
                            icon: Icon(
                              _full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                            ),
                            onPressed: _toggleFullscreen,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
