import 'package:flutter/material.dart';

import 'model.dart';

class SlideView extends StatelessWidget {
  const SlideView(this.slide, {super.key});
  final Slide slide;

  static const double w = 1280;
  static const double h = 720;
  static const double padX = 96;
  static const double padY = 80;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: w / h,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(width: w, height: h, child: _canvas()),
        ),
      ),
    );
  }

  Widget _canvas() {
    final t = kThemes[slide.theme.clamp(0, kThemes.length - 1).toInt()];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: t.gradient,
        ),
      ),
      child: Stack(
        children: [
          Positioned(right: -180, top: -200, child: _glow(640, t.accent.withValues(alpha: 0.22))),
          Positioned(left: -200, bottom: -260, child: _glow(560, t.accent.withValues(alpha: 0.12))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: padX, vertical: padY),
            child: switch (slide.layout) {
              SlideLayout.title => _titleLayout(t),
              SlideLayout.bullets => _bulletLayout(t),
              SlideLayout.quote => _quoteLayout(t),
            },
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, Color c) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)]),
        ),
      );

  Widget _titleLayout(DeckTheme t) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 96,
          height: 8,
          decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(height: 44),
        Text(
          slide.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: t.fg,
            fontSize: 104,
            fontWeight: FontWeight.w800,
            height: 1.04,
            letterSpacing: -2.5,
            decoration: TextDecoration.none,
          ),
        ),
        if (slide.body.trim().isNotEmpty) ...[
          const SizedBox(height: 32),
          Text(
            slide.body.trim(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.fg.withValues(alpha: 0.72),
              fontSize: 40,
              fontWeight: FontWeight.w400,
              height: 1.3,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ],
    );
  }

  Widget _bulletLayout(DeckTheme t) {
    final lines = slide.body
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          slide.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: t.fg,
            fontSize: 68,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -1.5,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 28),
        Container(
          width: 72,
          height: 6,
          decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(height: 44),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: w - padX * 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 26),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 19),
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
                            ),
                          ),
                          const SizedBox(width: 28),
                          Expanded(
                            child: Text(
                              line,
                              style: TextStyle(
                                color: t.fg.withValues(alpha: 0.92),
                                fontSize: 40,
                                height: 1.3,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _quoteLayout(DeckTheme t) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '\u201C',
          style: TextStyle(
            color: t.accent,
            fontSize: 220,
            fontWeight: FontWeight.w800,
            height: 0.7,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          slide.body.trim(),
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: t.fg,
            fontSize: 58,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
            height: 1.25,
            letterSpacing: -0.5,
            decoration: TextDecoration.none,
          ),
        ),
        if (slide.title.trim().isNotEmpty) ...[
          const SizedBox(height: 36),
          Text(
            '\u2014 ${slide.title.trim()}',
            style: TextStyle(
              color: t.fg.withValues(alpha: 0.7),
              fontSize: 34,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ],
    );
  }
}

