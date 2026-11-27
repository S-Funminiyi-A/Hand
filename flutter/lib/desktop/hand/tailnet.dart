import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

const Color kHandPurple = Color(0xFF582B7F);
const Color kHandYellow = Color(0xFFFAA41A);
const Color kHandOnline = Color(0xFF2E9E5B);
const String _kHostTag = 'tag:hand-host';
const String kHandNamesOption = 'hand-display-names';

enum HandPcKind { staff, mine }

class HandPc {
  final String key;
  final String hostName;
  final String ip;
  final String os;
  final bool online;
  final DateTime? lastSeen;
  final HandPcKind kind;
  HandPc({
    required this.key,
    required this.hostName,
    required this.ip,
    required this.os,
    required this.online,
    required this.lastSeen,
    required this.kind,
  });
}

class HandTailnetResult {
  final List<HandPc> pcs;
  final String? error;
  final bool selfIsHost;
  final String selfName;
  final List<String> ownerIps;
  HandTailnetResult(this.pcs,
      [this.error,
      this.selfIsHost = false,
      this.selfName = '',
      this.ownerIps = const []]);
}

String _displayHost(String host, HandPcKind kind) {
  if (kind != HandPcKind.staff || !host.startsWith('hand-')) return host;
  return host
      .substring(5)
      .split('-')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

Future<HandTailnetResult> readTailnet() async {
  const candidates = [
    r'C:\Program Files\Tailscale\tailscale.exe',
    'tailscale',
  ];
  ProcessResult? res;
  for (final exe in candidates) {
    if (exe.contains('\\') && !File(exe).existsSync()) continue;
    try {
      res = await Process.run(exe, ['status', '--json'])
          .timeout(const Duration(seconds: 6));
      break;
    } catch (_) {
      continue;
    }
  }
  if (res == null) {
    return HandTailnetResult([], 'not-installed');
  }
  if (res.exitCode != 0) {
    return HandTailnetResult([], 'not-running');
  }
  try {
    final data = jsonDecode(res.stdout as String) as Map<String, dynamic>;
    if (data['BackendState'] != 'Running') {
      return HandTailnetResult([], 'not-running');
    }
    final self = data['Self'] as Map<String, dynamic>? ?? {};
    final myUser = self['UserID'];
    final selfTags = (self['Tags'] as List?)?.cast<String>() ?? const [];
    final ownerIps = <String>[];
    final peers = (data['Peer'] as Map<String, dynamic>? ?? {}).values;
    final pcs = <HandPc>[];
    for (final p in peers) {
      final peer = p as Map<String, dynamic>;
      final tags = (peer['Tags'] as List?)?.cast<String>() ?? const [];
      final ips = (peer['TailscaleIPs'] as List?)?.cast<String>() ?? const [];
      final ipv4 = ips.firstWhere((ip) => !ip.contains(':'),
          orElse: () => ips.isEmpty ? '' : ips.first);
      if (ipv4.isEmpty) continue;
      if (tags.isEmpty && peer['Online'] == true) ownerIps.add(ipv4);
      HandPcKind? kind;
      if (tags.contains(_kHostTag)) {
        kind = HandPcKind.staff;
      } else if (tags.isEmpty &&
          peer['UserID'] == myUser &&
          (peer['OS'] as String? ?? '').toLowerCase() == 'windows') {
        kind = HandPcKind.mine;
      }
      if (kind == null) continue;
      pcs.add(HandPc(
        key: peer['ID']?.toString() ?? ipv4,
        hostName: _displayHost(peer['HostName'] as String? ?? ipv4, kind),
        ip: ipv4,
        os: peer['OS'] as String? ?? '',
        online: peer['Online'] == true,
        lastSeen: DateTime.tryParse(peer['LastSeen'] as String? ?? ''),
        kind: kind,
      ));
    }
    return HandTailnetResult(pcs, null, selfTags.contains(_kHostTag),
        self['HostName'] as String? ?? '', ownerIps);
  } catch (_) {
    return HandTailnetResult([], 'unreadable');
  }
}

