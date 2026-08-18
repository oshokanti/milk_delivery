import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key});

  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  double _totalCollected = 0;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('transactions')
          .select('*, shopkeepers(shop_name), profiles(name)')
          .order('collected_at', ascending: false);
      _transactions = List<Map<String, dynamic>>.from(response);
      _totalCollected = _transactions.fold<double>(0, (sum, t) => sum + (t['amount'] as double));
      setState(() => _isLoading = false);
    } catch (e) {
      print('Error: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment History'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Total Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Total Collections',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      Text(
                        '₹${_totalCollected.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      Text(
                        '${_transactions.length} transactions',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _transactions.isEmpty
                      ? const Center(child: Text('No transactions yet'))
                      : ListView.builder(
                          itemCount: _transactions.length,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemBuilder: (context, index) {
                            final t = _transactions[index];
                            final shopName = t['shopkeepers']?['shop_name'] ?? 'Unknown';
                            final collectedBy = t['profiles']?['name'] ?? 'Unknown';
                            final date = t['collected_at'] != null
                                ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(t['collected_at']))
                                : '';

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: t['method'] == 'cash'
                                      ? Colors.orange.shade100
                                      : Colors.blue.shade100,
                                  child: Icon(
                                    t['method'] == 'cash' ? Icons.currency_rupee : Icons.qr_code,
                                    color: t['method'] == 'cash' ? Colors.orange : Colors.blue,
                                  ),
                                ),
                                title: Text(shopName),
                                subtitle: Text('$date\nCollected by: $collectedBy'),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '₹${(t['amount'] as double).toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                    Text(
                                      t['method'] ?? '',
                                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}