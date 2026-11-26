import 'dart:math';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/main.dart';
import 'package:flutter_hbb/models/platform_model.dart';

final Set<int> _boundWindows = {};
_AspectArgs? _pending;

class _AspectArgs {
  final Size canvas;
  final int displayWidth;
  final int displayHeight;
  final String style;
  _AspectArgs(this.canvas, this.displayWidth, this.displayHeight, this.style);
}

Future<void> handBindAspectLock(int windowId, String peerId) async {
  if (!isWindows || _boundWindows.contains(windowId)) return;
  final token = 'hand-window-$windowId-${Random().nextInt(1 << 30)}';
  final controller = WindowController.fromWindowId(windowId);
  await controller.setTitle(token);
  final bound = bind.handAspectBind(windowId: windowId, token: token);
  await controller.setTitle(getWindowNameWithId(peerId));
  if (!bound) return;
  _boundWindows.add(windowId);
  final pending = _pending;
  if (pending != null) {
    _push(windowId, pending);
  }
}

void handUpdateAspectLock(
    Size canvas, int displayWidth, int displayHeight, String style) {
  final windowId = kWindowId;
  if (!isWindows || windowId == null) return;
  final args = _AspectArgs(canvas, displayWidth, displayHeight, style);
  _pending = args;
  if (_boundWindows.contains(windowId)) {
    _push(windowId, args);
  }
}

void _push(int windowId, _AspectArgs a) {
  if (a.style != kRemoteViewStyleAdaptive ||
      a.displayWidth <= 0 ||
      a.displayHeight <= 0 ||
      a.canvas.width <= 0 ||
      a.canvas.height <= 0) {
    bind.handAspectSet(windowId: windowId, ratio: 0, extraW: 0, extraH: 0);
    return;
  }
  final dpr = ui.window.devicePixelRatio;
  final view = ui.window.physicalSize;
  final extraW = max(0, (view.width - a.canvas.width * dpr).round());
  final extraH = max(0, (view.height - a.canvas.height * dpr).round());
  bind.handAspectSet(
      windowId: windowId,
      ratio: a.displayWidth / a.displayHeight,
      extraW: extraW,
      extraH: extraH);
}
