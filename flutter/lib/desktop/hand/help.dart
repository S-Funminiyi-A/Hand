import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';

import 'tailnet.dart';

const int kHandHelpPort = 21120;
const int _kMaxNote = 280;

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
  void Function(String ip, String note)? onNewRequest;
  ServerSocket? _server;

  Future<bool> listen() async {
    if (_server != null) return true;
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, kHandHelpPort);
    } catch (_) {
      return false;
    }
    _server!.listen(_handle, onError: (_) {});
    return true;
  }

  void clear(String ip) => requests.remove(ip);

  static bool _fromTailnet(InternetAddress a) {
    if (a.type != InternetAddressType.IPv4) return false;
    final b = a.rawAddress;
    return b[0] == 100 && (b[1] & 0xC0) == 64;
  }

  void _handle(Socket socket) {
    if (!_fromTailnet(socket.remoteAddress)) {
      socket.destroy();
      return;
    }
    final ip = socket.remoteAddress.address;
    utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .take(1)
        .timeout(const Duration(seconds: 5))
        .listen((line) {
      try {
        final msg = jsonDecode(line) as Map<String, dynamic>;
        final type = msg['type'];
        if (type == 'cancel') {
          requests.remove(ip);
        } else if (type == 'help') {
          var note = (msg['note'] as String? ?? '').trim();
          if (note.length > _kMaxNote) note = note.substring(0, _kMaxNote);
          requests[ip] = HandHelpRequest(ip, note, DateTime.now());
          onNewRequest?.call(ip, note);
        }
        socket.write('ok\n');
      } catch (_) {}
      socket.flush().whenComplete(socket.destroy);
    }, onError: (_) => socket.destroy(), cancelOnError: true);
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
