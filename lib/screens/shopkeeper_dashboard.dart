import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:milk_delivery/screens/place_order_screen.dart';
import 'package:milk_delivery/screens/order_history_screen.dart';

class ShopkeeperDashboard extends StatefulWidget {
  const ShopkeeperDashboard({super.key});

  @override
  State<ShopkeeperDashboard> createState() => _ShopkeeperDashboardState();
}

class _ShopkeeperDashboardState extends State<ShopkeeperDashboard> {
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? shopkeeper;
  bool isLoading = true;
  int pendingOrders = 0;
  double outstandingBalance = 0;
  int totalOrdersToday = 0;

  @override
  void initState() {
    super.initState();
    fetchShopkeeperData();
  }

  Future<void> fetchShopkeeperData() async {
    setState(() => isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final data = await supabase
          .from('shopkeepers')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (data != null) {
        setState(() {
          shopkeeper = data;
        });
        await fetchStats(data['id']);
      }
    } catch (e) {
      print('Error: $e');
    }
    setState(() => isLoading = false);
  }

  Future<void> fetchStats(String shopkeeperId) async {
    try {
      final pending = await supabase
          .from('orders')
          .select()
          .eq('shopkeeper_id', shopkeeperId)
          .eq('status', 'pending');

      final today = await supabase
          .from('orders')
          .select()
          .eq('shopkeeper_id', shopkeeperId)
          .eq('delivery_date', DateTime.now().toIso8601String().split('T')[0]);

      setState(() {
        pendingOrders = pending.length;
        totalOrdersToday = today.length;
        outstandingBalance = shopkeeper?['balance']?.toDouble() ?? 0;
      });
    } catch (e) {
      print('Stats error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopkeeper Dashboard'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await supabase.auth.signOut();
              Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : shopkeeper == null
              ? const Center(child: Text('No shop found. Please register.'))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome, ${shopkeeper!['shop_name']}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Owner: ${shopkeeper!['owner_name']}\nPhone: ${shopkeeper!['phone']}',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 24),

                      // Stats Cards
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              'Pending',
                              pendingOrders.toString(),
                              Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildStatCard(
                              "Today's Orders",
                              totalOrdersToday.toString(),
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildStatCard(
                              'Balance',
                              '₹${outstandingBalance.toStringAsFixed(2)}',
                              outstandingBalance > 0 ? Colors.red : Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      const Text(
                        'Quick Actions',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        shrinkWrap: true,
                        childAspectRatio: 1.5,
                        children: [
                          _buildActionCard(
                            icon: Icons.add_shopping_cart,
                            label: 'Place Order',
                            color: Colors.green,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PlaceOrderScreen(
                                    shopkeeperId: shopkeeper!['id'],
                                  ),
                                ),
                              );
                            },
                          ),
                          _buildActionCard(
                            icon: Icons.history,
                            label: 'Order History',
                            color: Colors.blue,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => OrderHistoryScreen(
                                    shopkeeperId: shopkeeper!['id'],
                                  ),
                                ),
                              );
                            },
                          ),
                          _buildActionCard(
                            icon: Icons.payment,
                            label: 'Pay Balance',
                            color: Colors.purple,
                            onTap: () {
                              // TODO: Payment screen
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Payment feature coming soon')),
                              );
                            },
                          ),
                          _buildActionCard(
                            icon: Icons.pause,
                            label: 'Pause Delivery',
                            color: Colors.orange,
                            onTap: () {
                              // TODO: Pause delivery
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Pause feature coming soon')),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
          ),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}