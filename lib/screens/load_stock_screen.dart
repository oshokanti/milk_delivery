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
  bool _hasMasterStock = false;

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
      // 1. Fetch products
      final productsData = await supabase
          .from('products')
          .select('*')
          .order('name');
      print('📦 Products fetched: ${productsData.length}');

      // 2. Check master stock for today
      final today = DateTime.now().toLocal().toString().split(' ')[0];
      final masterStockData = await supabase
          .from('master_stock')
          .select('id')
          .eq('date', today)
          .limit(1);
      _hasMasterStock = masterStockData.isNotEmpty;
      print('📦 Master stock exists today: $_hasMasterStock');

      // 3. Fetch existing driver stock
      final stockData = await supabase
          .from('driver_stock')
          .select('product_id, quantity_loaded')
          .eq('driver_id', widget.driverId)
          .eq('date', today);

      final stockMap = {for (var s in stockData) s['product_id']: s['quantity_loaded'] as int};

      setState(() {
        products = List<Map<String, dynamic>>.from(productsData);
        for (var product in products) {
          final id = product['id'];
          final qty = stockMap[id] ?? 0;
          controllers[id] = TextEditingController(text: qty.toString());
        }
        isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
      );
      setState(() => isLoading = false);
    }
  }

  Future<void> _saveStock() async {
    // ---- NEW: Check master stock ----
    if (!_hasMasterStock) {
      print('❌ Save blocked – no master stock for today.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Master stock not entered for today. Please contact admin.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

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

        // Upsert logic
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
      print('❌ Error saving stock: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error saving stock: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          : Column(
              children: [
                if (!_hasMasterStock)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '⚠️ Master stock not entered for today. Please ask admin to enter stock before loading.',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: products.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final id = product['id'];
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