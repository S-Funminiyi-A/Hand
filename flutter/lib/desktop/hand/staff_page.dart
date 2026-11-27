import 'package:flutter/material.dart';

import 'help.dart';
import 'tailnet.dart';

enum _AskState { idle, sending, sent, failed }

class HandStaffPage extends StatefulWidget {
  const HandStaffPage({Key? key}) : super(key: key);

  @override
  State<HandStaffPage> createState() => _HandStaffPageState();
}

class _HandStaffPageState extends State<HandStaffPage> {
  final _note = TextEditingController();
  _AskState _state = _AskState.idle;
  DateTime? _sentAt;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    setState(() => _state = _AskState.sending);
    final delivered =
        await HandHelp.instance.send({'type': 'help', 'note': _note.text});
    if (!mounted) return;
    setState(() {
      _state = delivered > 0 ? _AskState.sent : _AskState.failed;
      _sentAt = DateTime.now();
    });
  }

  Future<void> _cancel() async {
    await HandHelp.instance.send({'type': 'cancel'});
    if (!mounted) return;
    setState(() {
      _state = _AskState.idle;
      _note.clear();
    });
  }

  String _time(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: kHandOnline),
              ),
              const SizedBox(width: 8),
              Text('H&nd is on. Your admin can reach this PC.',
                  style: TextStyle(fontSize: 13, color: theme.hintColor)),
            ]),
            const SizedBox(height: 32),
            ..._content(theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(ThemeData theme) {
    const title = TextStyle(
        fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.4);
    const body = TextStyle(fontSize: 14, height: 1.5);
    switch (_state) {
      case _AskState.sent:
        return [
          const Text('Your admin has been told', style: title),
          const SizedBox(height: 8),
          Text(
              'Sent at ${_time(_sentAt!)}. Keep working. When they join, a small "Connected" bar shows on your screen.',
              style: body),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _cancel,
            style: _outlined(),
            child: const Text('Cancel request'),
          ),
        ];
      case _AskState.failed:
        return [
          const Text('Couldn\'t reach your admin', style: title),
          const SizedBox(height: 8),
          const Text(
              'Their PC may be off or offline. Try again in a few minutes.',
              style: body),
          const SizedBox(height: 24),
          ElevatedButton(
              onPressed: _ask, style: _primary(), child: const Text('Try again')),
        ];
      case _AskState.idle:
      case _AskState.sending:
        final sending = _state == _AskState.sending;
        return [
          const Text('Need a hand?', style: title),
          const SizedBox(height: 8),
          const Text(
              'Tell your admin what you\'re stuck on. They get a notification and can join your screen.',
              style: body),
          const SizedBox(height: 24),
          TextField(
            controller: _note,
            enabled: !sending,
            minLines: 3,
            maxLines: 5,
            maxLength: 280,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'What do you need help with? (optional)',
              hintStyle: TextStyle(fontSize: 14, color: theme.hintColor),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: kHandPurple, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: sending ? null : _ask,
            style: _primary(),
            child: Text(sending ? 'Sending…' : 'Ask for a hand'),
          ),
        ];
    }
  }

  ButtonStyle _primary() => ElevatedButton.styleFrom(
        backgroundColor: kHandPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(160, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );

  ButtonStyle _outlined() => OutlinedButton.styleFrom(
        foregroundColor: kHandPurple,
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );
}
