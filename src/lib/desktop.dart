import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// window_manager only exists on desktop; everything else falls back to
/// Flutter's immersive mode.
bool get isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows);

/// Real, OS-level fullscreen through window_manager.
abstract final class AppWindow {
  static bool _wasFullscreen = false;

  /// Enters fullscreen and remembers whether the window already was.
  static Future<void> enterFullscreen() async {
    if (!isDesktop) return;
    _wasFullscreen = await windowManager.isFullScreen();
    await windowManager.setFullScreen(true);
  }

  /// Puts the window back the way [enterFullscreen] found it.
  static Future<void> restore() async {
    if (!isDesktop) return;
    await windowManager.setFullScreen(_wasFullscreen);
  }

  /// Toggles fullscreen and returns the new state.
  static Future<bool> toggle() async {
    if (!isDesktop) return false;
    final next = !await windowManager.isFullScreen();
    await windowManager.setFullScreen(next);
    return next;
  }
}
