// lib/screens/account.dart
import 'package:flutter/material.dart';
import 'package:mixroom/widgets/main_drawer.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      drawer: const MainDrawer(),
      body: const Center(child: Text('Beta-testing', style: TextStyle(fontSize: 18))),
    );
  }
}
