import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:milk_delivery/screens/product_list_screen.dart';
import 'package:milk_delivery/screens/daily_stock_entry_screen.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.1,
          children: [
            _buildCard(
              context,
              icon: Icons.inventory,
              label: 'Products',
              color: Colors.blue,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProductListScreen()),
              ),
            ),
            _buildCard(
              context,
              icon: Icons.storage,
              label: 'Daily Stock',
              color: Colors.orange,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DailyStockEntryScreen()),
              ),
            ),
            _buildCard(
              context,
              icon: Icons.person,
              label: 'Drivers',
              color: Colors.green,
              onTap: () {
                // TODO: Driver management
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Driver management coming soon')),
                );
              },
            ),
            _buildCard(
              context,
              icon: Icons.store,
              label: 'Shopkeepers',
              color: Colors.purple,
              onTap: () {
                // TODO: Shopkeeper management
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Shopkeeper management coming soon')),
                );
              },
            ),
            _buildCard(
              context,
              icon: Icons.assessment,
              label: 'Reports',
              color: Colors.red,
              onTap: () {
                // TODO: Reports
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reports coming soon')),
                );
              },
            ),
            _buildCard(
              context,
              icon: Icons.settings,
              label: 'Settings',
              color: Colors.grey,
              onTap: () {
                // TODO: Settings
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings coming soon')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}