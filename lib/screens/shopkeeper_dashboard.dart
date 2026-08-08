import 'package:flutter/material.dart';

class ShopkeeperDashboard extends StatelessWidget {
  const ShopkeeperDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopkeeper Dashboard'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text('Welcome Shopkeeper!'),
      ),
    );
  }
}