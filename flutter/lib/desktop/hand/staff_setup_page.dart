import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:window_manager/window_manager.dart';

import 'tailnet.dart';

class HandSetupInfo {
  final bool staff;
  final String authKey;
  final String password;
  HandSetupInfo(this.staff, this.authKey, this.password);

  static HandSetupInfo read() {
    try {
      final m = jsonDecode(bind.handSetupInfo()) as Map<String, dynamic>;
      return HandSetupInfo(m['staff'] == true, m['authKey'] as String? ?? '',
          m['password'] as String? ?? '');
    } catch (_) {
      return HandSetupInfo(false, '', '');
    }
  }
}

String handHostSlug(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final cut = slug.length > 40 ? slug.substring(0, 40) : slug;
  return 'hand-$cut';
}

enum _SetupState { form, working, done, failed }

class HandStaffSetupPage extends StatefulWidget {
  final HandSetupInfo info;
  const HandStaffSetupPage({Key? key, required this.info}) : super(key: key);

  @override
  State<HandStaffSetupPage> createState() => _HandStaffSetupPageState();
}

class _HandStaffSetupPageState extends State<HandStaffSetupPage> {
  final _name = TextEditingController();
  _SetupState _state = _SetupState.form;
  String _error = '';
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _installedExe => '${bind.installInstallPath()}\\Hand.exe';

  String _psQuote(String s) => "'${s.replaceAll("'", "''")}'";

  Future<void> _setup() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _nameError = 'Enter your name so your admin knows it\'s you.');
      return;
    }
    setState(() {
      _nameError = null;
      _state = _SetupState.working;
    });

    final dir = Directory.systemTemp.createTempSync('hand-setup-');
    final log = '${dir.path}\\setup.log';
    final script = File('${dir.path}\\setup.ps1');
    final ts = r'$env:ProgramFiles\Tailscale\tailscale.exe';
    script.writeAsStringSync('''
\$ErrorActionPreference = 'Stop'
Start-Transcript -Path ${_psQuote(log)} | Out-Null
try {
  \$ts = "$ts"
  if (-not (Test-Path \$ts)) {
    \$msi = Join-Path \$env:TEMP 'tailscale-setup.msi'
    Invoke-WebRequest -UseBasicParsing 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi' -OutFile \$msi
    \$p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/i `"\$msi`" /qn TS_UNATTENDEDMODE=always"
    if (\$p.ExitCode -ne 0) { throw "Tailscale install failed (\$(\$p.ExitCode))" }
  }
  \$joined = \$false
  for (\$i = 0; \$i -lt 6 -and -not \$joined; \$i++) {
    & \$ts up --auth-key=${_psQuote(widget.info.authKey)} --hostname=${_psQuote(handHostSlug(name))} --advertise-tags=tag:hand-host --unattended --reset
    if (\$LASTEXITCODE -eq 0) { \$joined = \$true } else { Start-Sleep -Seconds 5 }
  }
  if (-not \$joined) { throw 'Could not join the company network' }
  powercfg /change standby-timeout-ac 0 | Out-Null
  powercfg /change hibernate-timeout-ac 0 | Out-Null
  & ${_psQuote(Platform.resolvedExecutable)} --silent-install | Out-Null
  \$hand = ${_psQuote(_installedExe)}
  for (\$i = 0; \$i -lt 30 -and -not (Test-Path \$hand); \$i++) { Start-Sleep -Seconds 2 }
  if (-not (Test-Path \$hand)) { throw 'H&nd did not install' }
  Start-Sleep -Seconds 5
  for (\$i = 0; \$i -lt 3; \$i++) {
    & \$hand --password ${_psQuote(widget.info.password)} | Out-Null
    Start-Sleep -Seconds 3
  }
  exit 0
} catch {
  Write-Output \$_
  exit 2
} finally {
  Stop-Transcript | Out-Null
}
''');

    final launcher = "try { \$p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru "
        "-WindowStyle Hidden -ErrorAction Stop -ArgumentList "
        "'-NoProfile -ExecutionPolicy Bypass -File \"${script.path}\"'; "
        "exit \$p.ExitCode } catch { exit 1 }";
    int code;
    try {
      final r = await Process.run(
          'powershell.exe', ['-NoProfile', '-Command', launcher]);
      code = r.exitCode;
    } catch (_) {
      code = -1;
    }
    try {
      script.deleteSync();
    } catch (_) {}
    if (!mounted) return;
    if (code == 0) {
      setState(() => _state = _SetupState.done);
      return;
    }
    String reason;
    if (code == 1) {
      reason = 'Windows permission was declined. Click Try again, then click Yes.';
    } else {
      reason = 'Something went wrong. Details are saved in $log. Send that file to your admin.';
    }
    setState(() {
      _state = _SetupState.failed;
      _error = reason;
    });
  }

  Future<void> _open() async {
    try {
      await Process.start(_installedExe, [], mode: ProcessStartMode.detached);
    } catch (_) {}
    await windowManager.close();
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(48, 56, 48, 32),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('H&nd',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: theme.hintColor)),
                const SizedBox(height: 24),
                ..._content(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(ThemeData theme) {
    const title = TextStyle(
        fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.6, height: 1.1);
    const body = TextStyle(fontSize: 15, height: 1.5);
    if (widget.info.authKey.isEmpty || widget.info.password.isEmpty) {
      return const [
        Text('This installer is incomplete', style: title),
        SizedBox(height: 12),
        Text(
            'It was built without its network key. Ask your admin for a new copy of Hand-Staff-Install.exe.',
            style: body),
      ];
    }
    switch (_state) {
      case _SetupState.working:
        return [
          const Text('Setting up H&nd', style: title),
          const SizedBox(height: 12),
          const Text('This takes about a minute. Keep this window open.',
              style: body),
          const SizedBox(height: 24),
          const LinearProgressIndicator(
              color: kHandPurple, backgroundColor: Color(0x1A582B7F)),
        ];
      case _SetupState.done:
        return [
          Text('All set, ${_name.text.trim().split(' ').first}', style: title),
          const SizedBox(height: 12),
          const Text(
              'H&nd now starts with Windows. When you\'re stuck, open H&nd and click Ask for a hand. Whenever your admin is on your PC, you\'ll see a "Connected" bar.',
              style: body),
          const SizedBox(height: 32),
          ElevatedButton(
              onPressed: _open, style: _primary(), child: const Text('Open H&nd')),
        ];
      case _SetupState.failed:
        return [
          const Text('Setup didn\'t finish', style: title),
          const SizedBox(height: 12),
          Text(_error, style: body),
          const SizedBox(height: 32),
          ElevatedButton(
              onPressed: _setup, style: _primary(), child: const Text('Try again')),
        ];
      case _SetupState.form:
        return [
          const Text('Set up H&nd on this PC', style: title),
          const SizedBox(height: 12),
          const Text(
              'Your admin uses H&nd to help with your work from their own desk. They can see and use this PC, and you\'ll always see a "Connected" bar when they do. This PC will stay awake while it\'s plugged in, so they can reach it after hours.',
              style: body),
          const SizedBox(height: 32),
          const Text('Your name',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            autofocus: true,
            onSubmitted: (_) => _setup(),
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: 'e.g. Amaka, Accounts',
              hintStyle: TextStyle(fontSize: 15, color: theme.hintColor),
              errorText: _nameError,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: kHandPurple, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
              onPressed: _setup, style: _primary(), child: const Text('Set up')),
          const SizedBox(height: 12),
          Text('Windows will ask for permission once. Click Yes.',
              style: TextStyle(fontSize: 13, color: theme.hintColor)),
        ];
    }
  }

  ButtonStyle _primary() => ElevatedButton.styleFrom(
        backgroundColor: kHandPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(160, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );
}
