import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrderHistoryScreen extends StatefulWidget {
  final String shopkeeperId;
  const OrderHistoryScreen({super.key, required this.shopkeeperId});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> orders = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchOrders();
  }

  Future<void> fetchOrders() async {
    setState(() => isLoading = true);
    try {
      final fifteenDaysAgo = DateTime.now().subtract(const Duration(days: 15));
      final response = await supabase
          .from('orders')
          .select('''
            *,
            order_items (
              product_id,
              quantity,
              price,
              total,
              products (name, unit)
            )
          ''')
          .eq('shopkeeper_id', widget.shopkeeperId)
          .gte('order_date', fifteenDaysAgo.toIso8601String().split('T')[0])
          .order('order_date', ascending: false);

      setState(() {
        orders = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    } catch (e) {
      print('Error: $e');
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order History (15 Days)'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : orders.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No orders in the last 15 days', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: orders.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    final items = order['order_items'] as List? ?? [];
                    final totalAmount = order['total_amount']?.toDouble() ?? 0;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              order['status'] == 'delivered' ? Colors.green : Colors.orange,
                          child: Icon(
                            order['status'] == 'delivered' ? Icons.check : Icons.pending,
                            color: Colors.white,
                          ),
                        ),
                        title: Text('Order #${order['id'].toString().substring(0, 8)}'),
                        subtitle: Text(
                          'Date: ${order['order_date']}  •  ₹${totalAmount.toStringAsFixed(2)}',
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Items:', style: TextStyle(fontWeight: FontWeight.bold)),
                                ...items.map((item) {
                                  final product = item['products'] as Map? ?? {};
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Text(
                                      '• ${product['name']} x ${item['quantity']} = ₹${(item['total'] ?? 0).toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  );
                                }).toList(),
                                const Divider(),
                                Text('Status: ${order['status'] ?? 'pending'}'),
                                Text('Payment: ${order['payment_status'] ?? 'pending'}'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}