import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:realtime_client/realtime_client.dart' show PostgresChangeEvent;

class AdminDeliveryTrackingScreen extends StatefulWidget {
  const AdminDeliveryTrackingScreen({super.key});

  @override
  State<AdminDeliveryTrackingScreen> createState() =>
      _AdminDeliveryTrackingScreenState();
}

class _AdminDeliveryTrackingScreenState
    extends State<AdminDeliveryTrackingScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> deliveries = [];
  bool isLoading = true;
  RealtimeChannel? _channel;

  // Stats
  int total = 0;
  int pending = 0;
  int inTransit = 0;
  int delivered = 0;

  @override
  void initState() {
    super.initState();
    _fetchDeliveries();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchDeliveries() async {
    setState(() => isLoading = true);
    try {
      final response = await supabase
          .from('deliveries')
          .select('*, profiles!deliveries_driver_id_fkey(name)')
          .order('created_at', ascending: false);

      setState(() {
        deliveries = List<Map<String, dynamic>>.from(response);
        _updateStats();
        isLoading = false;
      });
    } catch (e) {
      print('Error fetching deliveries: $e');
      setState(() => isLoading = false);
    }
  }

  void _updateStats() {
    total = deliveries.length;
    pending = deliveries.where((d) => d['status'] == 'pending').length;
    inTransit = deliveries.where((d) => d['status'] == 'in_transit').length;
    delivered = deliveries.where((d) => d['status'] == 'delivered').length;
  }

  void _subscribeToRealtime() {
    _channel = supabase
        .channel('deliveries_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'deliveries',
          callback: (payload) {
            _fetchDeliveries();
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Tracking'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Stats row
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      _buildStatCard('Total', total, Colors.blue),
                      _buildStatCard('Pending', pending, Colors.orange),
                      _buildStatCard('In Transit', inTransit, Colors.purple),
                      _buildStatCard('Delivered', delivered, Colors.green),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _fetchDeliveries,
                    child: ListView.builder(
                      itemCount: deliveries.length,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemBuilder: (context, index) {
                        final delivery = deliveries[index];
                        final driverName = delivery['profiles']?['name'] ?? 'Unknown';
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  _getStatusColor(delivery['status']),
                              child: Icon(
                                _getStatusIcon(delivery['status']),
                                color: Colors.white,
                              ),
                            ),
                            title: Text(delivery['shop_name'] ?? 'No shop'),
                            subtitle: Text(
                              'Driver: $driverName\nAddress: ${delivery['address']}\nItems: ${delivery['items']}',
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  (delivery['status'] ?? '').toUpperCase(),
                                  style: TextStyle(
                                    color: _getStatusColor(delivery['status']),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  delivery['scheduled_date'] ?? '',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatCard(String label, int count, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 12)),
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
        return Colors.purple;
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