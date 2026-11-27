import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

import 'tailnet.dart';

const int kHandHelpPort = 21120;

class HandHelpRequest {
  final String ip;
  final String note;
  final DateTime at;
  HandHelpRequest(this.ip, this.note, this.at);
}

class HandHelp {
  static final HandHelp instance = HandHelp._();
  HandHelp._();

  final RxMap<String, HandHelpRequest> requests =
      <String, HandHelpRequest>{}.obs;
  Timer? _poll;

  void watch() {
    _poll ??= Timer.periodic(const Duration(seconds: 2), (_) => _load());
    _load();
  }

  void _load() {
    try {
      final list = jsonDecode(bind.handHelpRequests()) as List<dynamic>;
      final next = <String, HandHelpRequest>{};
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final ip = m['ip'] as String? ?? '';
        if (ip.isEmpty) continue;
        next[ip] = HandHelpRequest(
            ip,
            m['note'] as String? ?? '',
            DateTime.fromMillisecondsSinceEpoch((m['at'] as num?)?.toInt() ?? 0));
      }
      final changed = next.length != requests.length ||
          next.entries.any((e) => requests[e.key]?.at != e.value.at);
      if (changed) requests.assignAll(next);
    } catch (_) {}
  }

  void clear(String ip) {
    bind.handHelpClear(ip: ip);
    requests.remove(ip);
  }

  Future<int> send(Map<String, dynamic> message) async {
    final net = await readTailnet();
    var delivered = 0;
    for (final ip in net.ownerIps) {
      Socket? socket;
      try {
        socket = await Socket.connect(ip, kHandHelpPort,
            timeout: const Duration(seconds: 4));
        socket.write('${jsonEncode(message)}\n');
        await socket.flush();
        final reply = await utf8.decoder
            .bind(socket)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 4));
        if (reply == 'ok') delivered++;
      } catch (_) {
      } finally {
        socket?.destroy();
      }
    }
    return delivered;
  }
}
