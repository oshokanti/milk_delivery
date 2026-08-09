import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/admin_dashboard.dart';
import 'screens/loading_screen.dart';
import 'screens/shopkeeper_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://bzbytphhzvwdtdjwlcwh.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ6Ynl0cGhoenZ3ZHRkandsY3doIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYxMTgxNzYsImV4cCI6MjEwMTY5NDE3Nn0.oQNu9Ls-aDT5yK9CM9v2Gjq0jmZ7VX6FZ9BtfAIOwko',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Medhya Farm',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
      routes: {
        '/admin': (context) => const AdminDashboard(),
        '/driver': (context) => const LoadingScreen(),
        '/shopkeeper': (context) => const ShopkeeperDashboard(),
      },
    );
  }
}