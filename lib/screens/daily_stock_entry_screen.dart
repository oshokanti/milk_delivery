import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:realtime_client/realtime_client.dart' show PostgresChangeEvent, PostgresChangePayload;

class DailyStockEntryScreen extends StatefulWidget {
  const DailyStockEntryScreen({super.key});

  @override
  State<DailyStockEntryScreen> createState() => _DailyStockEntryScreenState();
}

class _DailyStockEntryScreenState extends State<DailyStockEntryScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> products = [];
  Map<String, TextEditingController> stockControllers = {};
  bool isLoading = true;
  bool isSaving = false;
  String? today;
  RealtimeChannel? _stockChannel;

  @override
  void initState() {
    super.initState();
    today = DateTime.now().toIso8601String().split('T')[0];
    fetchData();
    _subscribeToStockChanges();
  }

  @override
  void dispose() {
    _stockChannel?.unsubscribe();
    _stockChannel = null;
    for (var controller in stockControllers.values) controller.dispose();
    super.dispose();
  }

  void _subscribeToStockChanges() {
    print('📡 Subscribing to master_stock changes...');
    _stockChannel = supabase.channel('master_stock_changes');
    _stockChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'master_stock',
          callback: (payload) => _handleStockChange(payload),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'master_stock',
          callback: (payload) => _handleStockChange(payload),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'master_stock',
          callback: (payload) => _handleStockChange(payload),
        )
        .subscribe((status, error) {
          if (error != null) {
            print('❌ Realtime error: $error');
          } else {
            print('✅ Subscribed to master_stock_changes');
          }
        });
  }

  void _handleStockChange(PostgresChangePayload payload) {
    final newData = payload.newRecord;
    if (newData != null && newData['date'] == today) {
      print('🔄 Master stock changed – refreshing...');
      fetchData();
    }
  }

  Future<void> fetchData() async {
    setState(() => isLoading = true);
    try {
      final productData = await supabase.from('products').select('*').order('name');
      final stockData = await supabase
          .from('master_stock')
          .select('product_id, remaining_quantity')
          .eq('date', today!);
      final stockMap = {for (var s in stockData) s['product_id']: s['remaining_quantity']};

      setState(() {
        products = List<Map<String, dynamic>>.from(productData);
        stockControllers.clear();
        for (var product in products) {
          final id = product['id'];
          stockControllers[id] = TextEditingController(
            text: (stockMap[id] ?? 0).toString(),
          );
        }
        isLoading = false;
      });
    } catch (e) {
      print('Error: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> saveStock() async {
    setState(() => isSaving = true);
    try {
      for (var product in products) {
        final id = product['id'];
        final controller = stockControllers[id];
        if (controller == null) continue;
        final qty = int.tryParse(controller.text.trim());
        if (qty == null || qty < 0) continue;

        final existing = await supabase
            .from('master_stock')
            .select('id')
            .eq('product_id', id)
            .eq('date', today!)
            .maybeSingle();

        if (existing != null) {
          await supabase
              .from('master_stock')
              .update({'remaining_quantity': qty})
              .eq('id', existing['id']);
        } else {
          await supabase.from('master_stock').insert({
            'product_id': id,
            'date': today!,
            'initial_quantity': qty,
            'remaining_quantity': qty,
          });
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock saved!'), backgroundColor: Colors.green),
      );
      await fetchData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Daily Stock - $today'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: fetchData),
          IconButton(icon: const Icon(Icons.save), onPressed: isSaving ? null : saveStock),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: products.length,
              padding: const EdgeInsets.all(8),
              itemBuilder: (context, index) {
                final product = products[index];
                final id = product['id'];
                final controller = stockControllers[id]!;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(product['name']),
                    subtitle: Text('Unit: ${product['unit']}'),
                    trailing: SizedBox(
                      width: 100,
                      child: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Qty',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}