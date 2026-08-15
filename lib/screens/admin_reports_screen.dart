import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;

  // Stats
  int _totalDeliveries = 0;
  double _totalRevenue = 0;
  int _totalReturns = 0;
  List<Map<String, dynamic>> _driverPerformance = [];
  List<Map<String, dynamic>> _shopkeeperBalances = [];

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    setState(() => _isLoading = true);
    try {
      final today = DateTime.now().toLocal().toString().split(' ')[0];

      // 1. Total deliveries today
      final deliveries = await supabase
          .from('deliveries')
          .select('*')
          .eq('delivered_at', today);
      _totalDeliveries = deliveries.length;

      // 2. Total revenue (sum of order item totals)
      double revenue = 0;
      for (var d in deliveries) {
        final items = d['items'] as List? ?? [];
        for (var item in items) {
          revenue += (item['price'] as num) * (item['quantity'] as int);
        }
      }
      _totalRevenue = revenue;

      // 3. Total returns (sum of return quantities)
      int returns = 0;
      for (var d in deliveries) {
        final ret = d['returns'] as List? ?? [];
        for (var r in ret) {
          returns += r['quantity'] as int;
        }
      }
      _totalReturns = returns;

      // 4. Driver performance (deliveries per driver today)
      final drivers = await supabase
          .from('profiles')
          .select('id, name')
          .eq('role', 'driver');
      _driverPerformance = [];
      for (var driver in drivers) {
        // Fetch deliveries for this driver
        final driverDeliveries = await supabase
            .from('deliveries')
            .select('id')
            .eq('driver_id', driver['id'])
            .eq('delivered_at', today);
        final count = driverDeliveries.length;
        _driverPerformance.add({
          'name': driver['name'] ?? 'Unknown',
          'count': count,
        });
      }
      // Sort by count descending
      _driverPerformance.sort((a, b) => b['count'].compareTo(a['count']));

      // 5. Shopkeeper balances
      final shops = await supabase
          .from('shopkeepers')
          .select('shop_name, balance')
          .order('balance', ascending: false);
      _shopkeeperBalances = List<Map<String, dynamic>>.from(shops);

      setState(() => _isLoading = false);
    } catch (e) {
      print('Error fetching reports: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Reports'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchReports,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary cards
                  Row(
                    children: [
                      _buildSummaryCard('Deliveries', '$_totalDeliveries', Colors.orange),
                      const SizedBox(width: 8),
                      _buildSummaryCard('Revenue', '₹${_totalRevenue.toStringAsFixed(0)}', Colors.green),
                      const SizedBox(width: 8),
                      _buildSummaryCard('Returns', '$_totalReturns', Colors.red),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Driver performance
                  const Text(
                    'Driver Performance (Today)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _driverPerformance.isEmpty
                      ? const Text('No deliveries yet today.')
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _driverPerformance.length,
                          itemBuilder: (context, index) {
                            final driver = _driverPerformance[index];
                            return ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(driver['name']),
                              trailing: Text('${driver['count']} deliveries'),
                            );
                          },
                        ),
                  const SizedBox(height: 24),

                  // Shopkeeper balances
                  const Text(
                    'Shopkeeper Balances',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _shopkeeperBalances.isEmpty
                      ? const Text('No shopkeepers yet.')
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _shopkeeperBalances.length,
                          itemBuilder: (context, index) {
                            final shop = _shopkeeperBalances[index];
                            final balance = (shop['balance'] ?? 0).toDouble();
                            return ListTile(
                              leading: const Icon(Icons.store),
                              title: Text(shop['shop_name'] ?? 'Unknown'),
                              trailing: Text(
                                '₹${balance.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: balance > 0 ? Colors.red : Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}