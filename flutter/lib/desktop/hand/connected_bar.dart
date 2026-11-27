import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:window_manager/window_manager.dart';

import 'tailnet.dart';

const Size kHandBarWindowSize = Size(300, 156);
bool _compact = false;

bool handUsesConnectedBar(Client client) =>
    client.authorized &&
    !client.disconnected &&
    !client.incomingVoiceCall &&
    client.type_() == ClientType.remote;

Future<void> _setCompact(bool compact) async {
  if (_compact == compact) return;
  _compact = compact;
  await windowManager.setSize(
      compact ? kHandBarWindowSize : kConnectionManagerWindowSizeClosedChat);
  await windowManager.setAlignment(Alignment.bottomRight);
}

void handRestoreCmSize() {
  if (_compact) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _setCompact(false));
  }
}

class HandConnectedBar extends StatefulWidget {
  final Client client;
  const HandConnectedBar({Key? key, required this.client}) : super(key: key);

  @override
  State<HandConnectedBar> createState() => _HandConnectedBarState();
}

class _HandConnectedBarState extends State<HandConnectedBar> {
  final DateTime _since = DateTime.now();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setCompact(true));
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _elapsed {
    final d = DateTime.now().difference(_since);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  void _toggleControl() {
    final client = widget.client;
    final enabled = !client.keyboard;
    bind.cmSwitchPermission(
        connId: client.id, name: 'keyboard', enabled: enabled);
    setState(() => client.keyboard = enabled);
  }

  void _end() => bind.cmCloseConnection(connId: widget.client.id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = widget.client;
    final who = client.name.trim().isEmpty ? 'Your admin' : client.name.trim();
    final paused = !client.keyboard;
    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: paused ? kHandYellow : kHandOnline,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$who is on your PC',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            Text(_elapsed,
                style: TextStyle(
                    fontSize: 13,
                    color: theme.hintColor,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
                (paused
                        ? 'You have control. They can watch but not click.'
                        : 'They can use your mouse and keyboard.') +
                    (client.inVoiceCall ? ' On a call.' : ''),
                style: TextStyle(fontSize: 12, color: theme.hintColor)),
          ),
          const Spacer(),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _toggleControl,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kHandPurple,
                  side: const BorderSide(color: kHandPurple),
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(paused ? 'Give control back' : 'Take back control',
                    style: const TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _end,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                minimumSize: const Size(64, 36),
              ),
              child: const Text('End', style: TextStyle(fontSize: 13)),
            ),
          ]),
        ],
      ),
    );
  }
}
