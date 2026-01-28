// lib/screens/notice.dart
import 'package:flutter/material.dart';
import 'package:mixroom/widgets/main_drawer.dart';

class NoticeScreen extends StatelessWidget {
  const NoticeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notice')),
      drawer: const MainDrawer(),
      body: const Center(child: Text('Beta-testing', style: TextStyle(fontSize: 18))),
    );
  }
}
