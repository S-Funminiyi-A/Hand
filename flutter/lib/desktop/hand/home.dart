import 'package:flutter/material.dart';

import 'people_page.dart';
import 'staff_page.dart';
import 'tailnet.dart';

class HandHome extends StatefulWidget {
  const HandHome({Key? key}) : super(key: key);

  @override
  State<HandHome> createState() => _HandHomeState();
}

class _HandHomeState extends State<HandHome> {
  late final Future<HandTailnetResult> _net = readTailnet();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HandTailnetResult>(
      future: _net,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(color: Theme.of(context).scaffoldBackgroundColor);
        }
        return snap.data!.selfIsHost
            ? const HandStaffPage()
            : const HandPeoplePage();
      },
    );
  }
}
