import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:milk_delivery/screens/delivery_detail_screen.dart';
import 'package:milk_delivery/screens/load_stock_screen.dart';

class DriverDashboard extends StatefulWidget {
  final String driverId;
  const DriverDashboard({super.key, required this.driverId});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  final supabase = Supabase.instance.client;
  late Future<Map<String, dynamic>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadDriverData();
  }

  Future<Map<String, dynamic>> _loadDriverData() async {
    try {
      final driverId = widget.driverId;

      final profileResponse = await supabase
          .from('profiles')
          .select('name')
          .eq('id', driverId)
          .maybeSingle();
      final driverName = profileResponse?['name'] ?? 'Driver';

      final response = await supabase
          .from('deliveries')
          .select('*')
          .eq('driver_id', driverId)
          .order('created_at');

      final List<Map<String, dynamic>> deliveries =
          (response as List?)?.cast<Map<String, dynamic>>() ?? [];

      final pendingCount = deliveries.where((d) => d['status'] != 'delivered').length;
      final deliveredCount = deliveries.where((d) => d['status'] == 'delivered').length;

      final today = DateTime.now().toLocal().toString().split(' ')[0];
      List<Map<String, dynamic>> stockItems = [];
      try {
        final stockData = await supabase
            .from('driver_stock')
            .select('*, products(name, unit)')
            .eq('driver_id', driverId)
            .eq('date', today);
        stockItems = List<Map<String, dynamic>>.from(stockData);
      } catch (e) {
        print('⚠️ Could not fetch stock items: $e');
      }

      return {
        'driverName': driverName,
        'deliveries': deliveries,
        'pendingCount': pendingCount,
        'deliveredCount': deliveredCount,
        'stockItems': stockItems,
        'error': null,
      };
    } catch (e) {
      print('❌ Error: $e');
      return {
        'error': e.toString(),
        'driverName': 'Driver',
        'deliveries': <Map<String, dynamic>>[],
        'pendingCount': 0,
        'deliveredCount': 0,
        'stockItems': <Map<String, dynamic>>[],
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _dataFuture = _loadDriverData();
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data!;
          final driverName = data['driverName'] as String? ?? 'Driver';
          final deliveries = (data['deliveries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          final pendingCount = data['pendingCount'] as int? ?? 0;
          final deliveredCount = data['deliveredCount'] as int? ?? 0;
          final stockItems = (data['stockItems'] as List?)?.cast<Map<String, dynamic>>() ?? [];

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _dataFuture = _loadDriverData();
              });
              await _dataFuture;
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome header
                  Text(
                    'Welcome, $driverName',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Today: ${DateTime.now().toLocal().toString().split(' ')[0]}',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),

// Stock in Vehicle – horizontal row with equal spacing and full width
const Text(
  'Stock in Vehicle',
  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
),
const SizedBox(height: 8),
stockItems.isEmpty
    ? const Text('No stock loaded today', style: TextStyle(color: Colors.grey))
    : Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: stockItems.map((item) {
          final product = item['products'] as Map? ?? {};
          final name = product['name'] ?? 'Unknown';
          final quantity = item['quantity_loaded'] as int? ?? 0;
          final unit = product['unit'] ?? '';

          final List<Color> colors = [
            Colors.blue.shade100,
            Colors.teal.shade100,
            Colors.green.shade100,
            Colors.orange.shade100,
            Colors.purple.shade100,
            Colors.pink.shade100,
            Colors.indigo.shade100,
            Colors.lime.shade100,
          ];
          final Color bgColor = colors[stockItems.indexOf(item) % colors.length];
          final Color accentColor = bgColor.computeLuminance() > 0.5
              ? Colors.black87
              : Colors.white;

          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    spreadRadius: 2,
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$quantity',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: accentColor.withOpacity(0.8),
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (unit.isNotEmpty)
                    Text(
                      unit,
                      style: TextStyle(
                        fontSize: 10,
                        color: accentColor.withOpacity(0.6),
                      ),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
const SizedBox(height: 16),
                  // Stats cards
                  Row(
                    children: [
                      _buildStatCard('Pending', '$pendingCount', Colors.orange),
                      const SizedBox(width: 8),
                      _buildStatCard('Delivered', '$deliveredCount', Colors.green),
                      const SizedBox(width: 8),
                      _buildStatCard('Total Stock', '${stockItems.fold<int>(0, (sum, item) => sum + (item['quantity_loaded'] as int? ?? 0))}', Colors.blue),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Actions row
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LoadStockScreen(driverId: widget.driverId),
                              ),
                            );
                            if (result == true) {
                              setState(() {
                                _dataFuture = _loadDriverData();
                              });
                            }
                          },
                          icon: const Icon(Icons.inventory),
                          label: const Text('Load Stock'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Start Day coming soon')),
                            );
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start Day'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Today's Deliveries title
                  const Text(
                    'Today\'s Deliveries',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  // Deliveries list
                  deliveries.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32.0),
                            child: Text('No deliveries today'),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: deliveries.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) {
                            final delivery = deliveries[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getStatusColor(delivery['status']),
                                child: Icon(
                                  _getStatusIcon(delivery['status']),
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(delivery['shop_name'] ?? 'Unknown'),
                              subtitle: Text(
                                '${delivery['address'] ?? ''}\nItems: ${delivery['items'] ?? ''}',
                              ),
                              trailing: Text(
                                (delivery['status'] ?? 'pending').toUpperCase(),
                                style: TextStyle(
                                  color: _getStatusColor(delivery['status']),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onTap: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DeliveryDetailScreen(
                                      delivery: delivery,
                                      driverId: widget.driverId,
                                    ),
                                  ),
                                );
                                if (result == true) {
                                  setState(() {
                                    _dataFuture = _loadDriverData();
                                  });
                                }
                              },
                            );
                          },
                        ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
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

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'delivered':
        return Colors.green;
      case 'in_transit':
        return Colors.blue;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status) {
      case 'delivered':
        return Icons.check_circle;
      case 'in_transit':
        return Icons.delivery_dining;
      case 'pending':
        return Icons.pending;
      default:
        return Icons.help;
    }
  }
}