// lib/screens/howto.dart
import 'package:flutter/material.dart';
import 'package:mixroom/widgets/main_drawer.dart';

class HowtoScreen extends StatelessWidget {
  const HowtoScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Howto')),
      drawer: const MainDrawer(),
      body: const Center(child: Text('Beta-testing', style: TextStyle(fontSize: 18))),
    );
  }
}
