import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  void initState() {
    super.initState();
    today = DateTime.now().toIso8601String().split('T')[0];
    fetchData();
  }

  Future<void> fetchData() async {
    setState(() => isLoading = true);
    try {
      // Fetch all active products
      final productData = await supabase.from('products').select('*').order('name');

      // Fetch today's stock entries
      final stockData = await supabase
          .from('master_stock')
          .select('*')
          .eq('date', today!);

      // Map product_id -> stock entry
      final stockMap = {for (var s in stockData) s['product_id']: s};

      setState(() {
        products = List<Map<String, dynamic>>.from(productData);
        stockControllers = {};
        for (var product in products) {
          final id = product['id'];
          final existing = stockMap[id];
          final initial = existing != null ? existing['initial_quantity'].toString() : '';
          stockControllers[id] = TextEditingController(text: initial);
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
        final value = stockControllers[id]?.text.trim() ?? '';
        if (value.isEmpty) continue;
        final quantity = int.tryParse(value);
        if (quantity == null || quantity < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invalid quantity for ${product['name']}'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() => isSaving = false);
          return;
        }

        // Check if stock entry exists for today
        final existing = await supabase
            .from('master_stock')
            .select()
            .eq('product_id', id)
            .eq('date', today!)
            .maybeSingle();

        if (existing != null) {
          // Update
          await supabase
              .from('master_stock')
              .update({
                'initial_quantity': quantity,
                'remaining_quantity': quantity, // reset remaining to initial
              })
              .eq('id', existing['id']);
        } else {
          // Insert
          await supabase.from('master_stock').insert({
            'product_id': id,
            'date': today!,
            'initial_quantity': quantity,
            'remaining_quantity': quantity,
          });
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock saved successfully'), backgroundColor: Colors.green),
      );
      await fetchData(); // Refresh
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
      );
    }
    setState(() => isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Daily Stock Entry - $today'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: isSaving ? null : saveStock,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Enter initial stock for each product for today',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: products.length,
                    padding: const EdgeInsets.all(8),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final id = product['id'];
                      final controller = stockControllers[id] ?? TextEditingController();
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
                              onChanged: (value) {
                                // Update controller map (optional)
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: isSaving ? null : saveStock,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Save Stock', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}