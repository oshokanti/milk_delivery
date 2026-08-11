import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoadStockScreen extends StatefulWidget {
  final String driverId;
  const LoadStockScreen({super.key, required this.driverId});

  @override
  State<LoadStockScreen> createState() => _LoadStockScreenState();
}

class _LoadStockScreenState extends State<LoadStockScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> products = [];
  Map<String, TextEditingController> controllers = {};
  bool isLoading = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    for (var controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => isLoading = true);
    try {
      // Fetch all products
      final productsData = await supabase
          .from('products')
          .select('*')
          .order('name');
      print('📦 Products fetched: ${productsData.length}');

      // Convert to list
      final List<Map<String, dynamic>> productList =
          List<Map<String, dynamic>>.from(productsData);

      setState(() {
        products = productList;
        for (var product in products) {
          controllers[product['id']] = TextEditingController(text: '0');
        }
      });

      // Now fetch existing stock for today
      try {
        final today = DateTime.now().toLocal().toString().split(' ')[0];
        final stockData = await supabase
            .from('driver_stock')
            .select('product_id, quantity_loaded')
            .eq('driver_id', widget.driverId)
            .eq('date', today);

        print('📦 Stock found: ${stockData.length} entries');

        // Build a map of product_id -> quantity
        final stockMap = {for (var s in stockData) s['product_id']: s['quantity_loaded'] as int};

        // Update controllers with existing quantities
        setState(() {
          for (var product in products) {
            final id = product['id'];
            final qty = stockMap[id] ?? 0;
            controllers[id]?.text = qty.toString();
          }
        });
      } catch (stockError) {
        // If stock table doesn't exist or any other error, just use zeros
        print('⚠️ Could not fetch existing stock: $stockError');
      }

      setState(() => isLoading = false);
    } catch (e) {
      print('❌ Error loading products: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading products: $e'), backgroundColor: Colors.red),
      );
      setState(() => isLoading = false);
    }
  }

  Future<void> _saveStock() async {
    setState(() => isSaving = true);
    try {
      final today = DateTime.now().toLocal().toString().split(' ')[0];
      for (var product in products) {
        final id = product['id'];
        final controller = controllers[id];
        if (controller == null) continue;
        final text = controller.text.trim();
        final quantity = int.tryParse(text);
        if (quantity == null || quantity < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid quantity for ${product['name']}'), backgroundColor: Colors.orange),
          );
          setState(() => isSaving = false);
          return;
        }

        // Upsert
        final existing = await supabase
            .from('driver_stock')
            .select('id')
            .eq('driver_id', widget.driverId)
            .eq('product_id', id)
            .eq('date', today)
            .maybeSingle();

        if (existing != null) {
          await supabase
              .from('driver_stock')
              .update({'quantity_loaded': quantity})
              .eq('id', existing['id']);
        } else {
          await supabase.from('driver_stock').insert({
            'driver_id': widget.driverId,
            'product_id': id,
            'quantity_loaded': quantity,
            'date': today,
          });
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Stock saved successfully!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error saving stock: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🔍 Build: isLoading=$isLoading, products.length=${products.length}');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Load Stock'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: isSaving ? null : _saveStock,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : products.isEmpty
              ? const Center(child: Text('No products available'))
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: products.length,
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          final product = products[index];
                          final id = product['id'];
                          if (!controllers.containsKey(id)) {
                            controllers[id] = TextEditingController(text: '0');
                          }
                          final controller = controllers[id]!;
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product['name'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          'Unit: ${product['unit']}  •  Price: ₹${product['price']}',
                                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: 80,
                                    child: TextField(
                                      controller: controller,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Qty',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
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
                          onPressed: isSaving ? null : _saveStock,
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