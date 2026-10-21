import 'dart:io';

import 'package:window_manager/window_manager.dart';

/// Fully quit the menu-bar app (window + tray process).
Future<void> quitAppCompletely() async {
  try {
    await windowManager.destroy();
  } catch (_) {
    // Process exit is enough if the window is already gone.
  }
  exit(0);
}
