import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverPaymentScreen extends StatefulWidget {
  final String driverId;
  const DriverPaymentScreen({super.key, required this.driverId});

  @override
  State<DriverPaymentScreen> createState() => _DriverPaymentScreenState();
}

class _DriverPaymentScreenState extends State<DriverPaymentScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _shopkeepers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('shopkeepers')
          .select('id, shop_name, balance')
          .gt('balance', 0) // only those with outstanding balance
          .order('balance', ascending: false);
      _shopkeepers = List<Map<String, dynamic>>.from(response);
      setState(() => _isLoading = false);
    } catch (e) {
      print('Error fetching shopkeepers: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _collectPayment(Map<String, dynamic> shop) async {
    final TextEditingController amountController = TextEditingController(
      text: (shop['balance'] as double).toStringAsFixed(2),
    );
    String selectedMethod = 'cash';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Collect Payment - ${shop['shop_name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Outstanding Balance: ₹${shop['balance']}'),
            const SizedBox(height: 8),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount to collect',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: selectedMethod,
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'upi', child: Text('UPI')),
                DropdownMenuItem(value: 'online', child: Text('Online')),
              ],
              onChanged: (value) {
                if (value != null) selectedMethod = value;
              },
              decoration: const InputDecoration(
                labelText: 'Payment Method',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text.trim());
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a valid amount'), backgroundColor: Colors.orange),
                );
                return;
              }
              if (amount > (shop['balance'] as double)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Amount exceeds outstanding balance'), backgroundColor: Colors.orange),
                );
                return;
              }

              try {
                // 1. Insert transaction
                await supabase.from('transactions').insert({
                  'shopkeeper_id': shop['id'],
                  'amount': amount,
                  'method': selectedMethod,
                  'collected_by': widget.driverId,
                  'collected_at': DateTime.now().toUtc().toIso8601String(),
                });

                // 2. Update shopkeeper balance
                final newBalance = (shop['balance'] as double) - amount;
                await supabase
                    .from('shopkeepers')
                    .update({'balance': newBalance})
                    .eq('id', shop['id']);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ Payment collected!'), backgroundColor: Colors.green),
                );
                Navigator.pop(context);
                await _fetchData();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Collect Payment'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collect Payments'),
        backgroundColor: Colors.teal,
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
          : _shopkeepers.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, size: 64, color: Colors.green),
                      SizedBox(height: 16),
                      Text('No outstanding balances'),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _shopkeepers.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) {
                    final shop = _shopkeepers[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.store, color: Colors.teal),
                        title: Text(shop['shop_name']),
                        subtitle: Text(
                          'Outstanding: ₹${(shop['balance'] as double).toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.red),
                        ),
                        trailing: ElevatedButton.icon(
                          onPressed: () => _collectPayment(shop),
                          icon: const Icon(Icons.payment),
                          label: const Text('Collect'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}