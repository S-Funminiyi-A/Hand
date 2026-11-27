import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';

const Color kHandPurple = Color(0xFF582B7F);
const Color kHandYellow = Color(0xFFFAA41A);
const Color kHandOnline = Color(0xFF2E9E5B);
const String _kHostTag = 'tag:hand-host';
const String _kNamesOption = 'hand-display-names';

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
  HandTailnetResult(this.pcs, [this.error]);
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
    final peers = (data['Peer'] as Map<String, dynamic>? ?? {}).values;
    final pcs = <HandPc>[];
    for (final p in peers) {
      final peer = p as Map<String, dynamic>;
      final tags = (peer['Tags'] as List?)?.cast<String>() ?? const [];
      final ips = (peer['TailscaleIPs'] as List?)?.cast<String>() ?? const [];
      final ipv4 = ips.firstWhere((ip) => !ip.contains(':'),
          orElse: () => ips.isEmpty ? '' : ips.first);
      if (ipv4.isEmpty) continue;
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
        hostName: peer['HostName'] as String? ?? ipv4,
        ip: ipv4,
        os: peer['OS'] as String? ?? '',
        online: peer['Online'] == true,
        lastSeen: DateTime.tryParse(peer['LastSeen'] as String? ?? ''),
        kind: kind,
      ));
    }
    return HandTailnetResult(pcs);
  } catch (_) {
    return HandTailnetResult([], 'unreadable');
  }
}

Map<String, String> _loadNames() {
  try {
    final raw = bind.mainGetLocalOption(key: _kNamesOption);
    if (raw.isEmpty) return {};
    return (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
  } catch (_) {
    return {};
  }
}

void _saveNames(Map<String, String> names) {
  bind.mainSetLocalOption(key: _kNamesOption, value: jsonEncode(names));
}

String _lastSeenText(HandPc pc) {
  if (pc.online) return 'Online';
  final seen = pc.lastSeen;
  if (seen == null || seen.year < 2000) return 'Offline';
  final d = DateTime.now().difference(seen.toLocal());
  if (d.inMinutes < 1) return 'Offline · seen just now';
  if (d.inMinutes < 60) return 'Offline · seen ${d.inMinutes} min ago';
  if (d.inHours < 24) return 'Offline · seen ${d.inHours} h ago';
  return 'Offline · seen ${d.inDays} d ago';
}

class HandPeoplePage extends StatefulWidget {
  const HandPeoplePage({Key? key}) : super(key: key);

  @override
  State<HandPeoplePage> createState() => _HandPeoplePageState();
}

class _HandPeoplePageState extends State<HandPeoplePage> {
  HandTailnetResult? _result;
  Map<String, String> _names = {};
  String _query = '';
  Timer? _timer;
  final _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _names = _loadNames();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final r = await readTailnet();
    if (mounted) setState(() => _result = r);
  }

  String _nameOf(HandPc pc) => _names[pc.key] ?? pc.hostName;

  void _rename(HandPc pc, String name) {
    final trimmed = name.trim();
    setState(() {
      if (trimmed.isEmpty || trimmed == pc.hostName) {
        _names.remove(pc.key);
      } else {
        _names[pc.key] = trimmed;
      }
    });
    _saveNames(_names);
  }

  void _askToHelp(HandPc pc) =>
      connect(context, pc.ip, loginMethod: 'request-approval');

  void _takeOver(HandPc pc) => connect(context, pc.ip);

  void _connectAddress() {
    final address = _addressController.text.trim();
    if (address.isEmpty) return;
    connect(context, address);
  }

  List<HandPc> _filtered(HandPcKind kind) {
    final q = _query.toLowerCase();
    final list = (_result?.pcs ?? [])
        .where((p) => p.kind == kind)
        .where((p) =>
            q.isEmpty ||
            _nameOf(p).toLowerCase().contains(q) ||
            p.ip.contains(q))
        .toList();
    list.sort((a, b) {
      if (a.online != b.online) return a.online ? -1 : 1;
      return _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase());
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(theme),
          const SizedBox(height: 24),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: [
        Text('People',
            style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4)),
        const Spacer(),
        SizedBox(
          width: 220,
          height: 36,
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(fontSize: 14),
            decoration: _inputDecoration(theme, 'Search people',
                prefix: Icons.search_rounded),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 200,
          height: 36,
          child: TextField(
            controller: _addressController,
            onSubmitted: (_) => _connectAddress(),
            style: const TextStyle(fontSize: 14),
            decoration: _inputDecoration(theme, 'Connect to address',
                prefix: Icons.arrow_forward_rounded),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(ThemeData theme, String hint,
      {IconData? prefix}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: theme.dividerColor),
    );
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: TextStyle(fontSize: 14, color: theme.hintColor),
      prefixIcon: prefix == null ? null : Icon(prefix, size: 16),
      prefixIconConstraints: const BoxConstraints(minWidth: 32),
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: kHandPurple, width: 1.5)),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final result = _result;
    if (result == null) return const _SkeletonList();
    if (result.error != null) {
      return _Notice(
        title: result.error == 'not-installed'
            ? 'Tailscale isn\'t installed on this PC'
            : 'Tailscale isn\'t connected',
        body: result.error == 'not-installed'
            ? 'H&nd reaches PCs through Tailscale. Install it, sign in, then try again.'
            : 'Open Tailscale from the taskbar and sign in, then try again.',
        action: 'Try again',
        onAction: () {
          setState(() => _result = null);
          _refresh();
        },
      );
    }
    final staff = _filtered(HandPcKind.staff);
    final mine = _filtered(HandPcKind.mine);
    if (staff.isEmpty && mine.isEmpty) {
      return _Notice(
        title: _query.isEmpty ? 'No PCs yet' : 'Nobody matches "$_query"',
        body: _query.isEmpty
            ? 'Install H&nd on a staff PC and it shows up here within a minute.'
            : 'Check the spelling, or search by name or address.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (staff.isNotEmpty) ...[
          _SectionLabel('Staff', staff.where((p) => p.online).length,
              staff.length),
          ...staff.map((pc) => _PcRow(
                pc: pc,
                name: _nameOf(pc),
                onRename: (n) => _rename(pc, n),
                primaryLabel: 'Take over',
                onPrimary: () => _takeOver(pc),
                secondaryLabel: 'Ask to help',
                onSecondary: () => _askToHelp(pc),
              )),
          const SizedBox(height: 24),
        ],
        if (mine.isNotEmpty) ...[
          _SectionLabel('My PCs', mine.where((p) => p.online).length,
              mine.length),
          ...mine.map((pc) => _PcRow(
                pc: pc,
                name: _nameOf(pc),
                onRename: (n) => _rename(pc, n),
                primaryLabel: 'Open',
                onPrimary: () => _takeOver(pc),
              )),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final int online;
  final int total;
  const _SectionLabel(this.label, this.online, this.total);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text('$online of $total online',
              style: TextStyle(fontSize: 13, color: theme.hintColor)),
        ],
      ),
    );
  }
}

class _PcRow extends StatefulWidget {
  final HandPc pc;
  final String name;
  final ValueChanged<String> onRename;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _PcRow({
    required this.pc,
    required this.name,
    required this.onRename,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  State<_PcRow> createState() => _PcRowState();
}

class _PcRowState extends State<_PcRow> {
  bool _hover = false;
  bool _editing = false;
  late final TextEditingController _edit =
      TextEditingController(text: widget.name);
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _edit.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEdit() {
    _edit.text = widget.name;
    _edit.selection =
        TextSelection(baseOffset: 0, extentOffset: widget.name.length);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _finishEdit(bool save) {
    if (save) widget.onRename(_edit.text);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pc = widget.pc;
    final rowColor = _hover ? theme.hoverColor : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: rowColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: pc.online ? kHandOnline : theme.disabledColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: _buildName(theme, pc)),
            if (widget.secondaryLabel != null) ...[
              TextButton(
                onPressed: pc.online ? widget.onSecondary : null,
                style: TextButton.styleFrom(
                  foregroundColor: kHandPurple,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(0, 36),
                ),
                child: Text(widget.secondaryLabel!,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 8),
            ],
            ElevatedButton(
              onPressed: pc.online ? widget.onPrimary : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: kHandPurple,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: const Size(96, 36),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(widget.primaryLabel,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildName(ThemeData theme, HandPc pc) {
    if (_editing) {
      return Focus(
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
            _finishEdit(false);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SizedBox(
          width: 260,
          height: 32,
          child: TextField(
            controller: _edit,
            focusNode: _focus,
            onSubmitted: (_) => _finishEdit(true),
            onTapOutside: (_) => _finishEdit(true),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
            ),
          ),
        ),
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: GestureDetector(
                onDoubleTap: _startEdit,
                child: Text(widget.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ),
            ),
            if (_hover)
              Tooltip(
                message: 'Rename',
                child: InkWell(
                  onTap: _startEdit,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.edit_outlined,
                        size: 14, color: theme.hintColor),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text('${_lastSeenText(pc)} · ${pc.ip}',
            style: TextStyle(fontSize: 12, color: theme.hintColor)),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;
  const _Notice(
      {required this.title, required this.body, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(body,
                style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: theme.textTheme.bodyMedium?.color)),
            if (action != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kHandPurple,
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(action!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    final bar = Theme.of(context).dividerColor;
    Widget block(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
              color: bar, borderRadius: BorderRadius.circular(4)),
        );
    return Column(
      children: List.generate(
        4,
        (_) => SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 16),
              block(8, 8),
              const SizedBox(width: 16),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [block(160, 12), const SizedBox(height: 6), block(110, 10)],
              ),
              const Spacer(),
              block(96, 36),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}
