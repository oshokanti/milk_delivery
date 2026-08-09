import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/admin_dashboard.dart';
import 'screens/loading_screen.dart';
import 'screens/shopkeeper_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',      // Replace with your actual URL
    anonKey: 'YOUR_SUPABASE_ANON_KEY', // Replace with your actual anon key
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
