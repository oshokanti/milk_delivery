import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeliveryDetailScreen extends StatefulWidget {
  final Map<String, dynamic> delivery;
  final String driverId;
  const DeliveryDetailScreen({super.key, required this.delivery, required this.driverId});

  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> products = [];
  Map<String, TextEditingController> controllers = {};
  bool isLoading = true;
  bool isSaving = false;
  String _selectedStatus = 'pending';

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.delivery['status'] ?? 'pending';
    _fetchProducts();
  }

  Future<void> _fetchProducts() async {
    setState(() => isLoading = true);
    try {
      // Fetch all products
      final productsData = await supabase.from('products').select('*').order('name');
      setState(() {
        products = List<Map<String, dynamic>>.from(productsData);
        // Initialize controllers with 0
        for (var product in products) {
          controllers[product['id']] = TextEditingController(text: '0');
        }
        // If there are existing items in the delivery, pre-fill them
        final existingItems = widget.delivery['items'] as List? ?? [];
        for (var item in existingItems) {
          final productId = item['product_id'];
          final quantity = item['quantity'] as int? ?? 0;
          if (controllers.containsKey(productId)) {
            controllers[productId]?.text = quantity.toString();
          }
        }
        isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading products: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
      setState(() => isLoading = false);
    }
  }

  Future<void> _confirmDelivery() async {
    setState(() => isSaving = true);

    try {
      // 1. Build the items list (only products with quantity > 0)
      final List<Map<String, dynamic>> items = [];
      for (var product in products) {
        final id = product['id'];
        final controller = controllers[id];
        if (controller == null) continue;
        final qty = int.tryParse(controller.text.trim());
        if (qty != null && qty > 0) {
          items.add({
            'product_id': id,
            'quantity': qty,
          });
        }
      }

      // 2. Update delivery: status = 'delivered', items = items
      await supabase
          .from('deliveries')
          .update({
            'status': 'delivered',
            'items': items,
          })
          .eq('id', widget.delivery['id']);

      // 3. Deduct delivered quantities from driver_stock (for today)
      if (items.isNotEmpty) {
        final today = DateTime.now().toLocal().toString().split(' ')[0];
        for (var item in items) {
          final productId = item['product_id'];
          final qty = item['quantity'];

          // Fetch current stock for this product
          final stockRecord = await supabase
              .from('driver_stock')
              .select('id, quantity_loaded')
              .eq('driver_id', widget.driverId)
              .eq('product_id', productId)
              .eq('date', today)
              .maybeSingle();

          if (stockRecord != null) {
            final currentStock = stockRecord['quantity_loaded'] as int;
            final newStock = currentStock - qty;
            if (newStock < 0) {
              throw Exception('Not enough stock for product $productId');
            }
            await supabase
                .from('driver_stock')
                .update({'quantity_loaded': newStock})
                .eq('id', stockRecord['id']);
          } else {
            // If no stock record, can't deduct (should not happen)
            throw Exception('No stock found for product $productId');
          }
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Delivery confirmed and stock updated!'), backgroundColor: Colors.green),
      );
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final delivery = widget.delivery;
    return Scaffold(
      appBar: AppBar(
        title: Text(delivery['shop_name'] ?? 'Delivery Detail'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Shop info card
                    Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              delivery['shop_name'] ?? 'Unknown Shop',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text('📍 ${delivery['address'] ?? 'No address'}'),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text('Current Status: ', style: TextStyle(fontWeight: FontWeight.w500)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(_selectedStatus),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _selectedStatus.toUpperCase(),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Product quantities section
                    const Text(
                      'Enter Delivered Quantities',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    ...products.map((product) {
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
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                    }).toList(),

                    const SizedBox(height: 24),

                    // Confirm Delivery Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSaving ? null : _confirmDelivery,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isSaving
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Confirm Delivery', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ],
                ),
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
}