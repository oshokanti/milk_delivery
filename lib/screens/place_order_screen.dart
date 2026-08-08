import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlaceOrderScreen extends StatefulWidget {
  final String shopkeeperId;

  const PlaceOrderScreen({super.key, required this.shopkeeperId});

  @override
  State<PlaceOrderScreen> createState() => _PlaceOrderScreenState();
}

class _PlaceOrderScreenState extends State<PlaceOrderScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> products = [];
  Map<String, int> quantities = {};
  Map<String, TextEditingController> controllers = {};
  Map<String, FocusNode> focusNodes = {};

  bool isLoading = true;
  bool isSaving = false;
  DateTime selectedDeliveryDate = DateTime.now().add(const Duration(days: 1));
  String? selectedPaymentMethod;

  @override
  void initState() {
    super.initState();
    fetchProducts();
  }

  @override
  void dispose() {
    for (var controller in controllers.values) {
      controller.dispose();
    }
    for (var focusNode in focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> fetchProducts() async {
    setState(() => isLoading = true);

    try {
      final response = await supabase.from('products').select();
      setState(() {
        products = List<Map<String, dynamic>>.from(response);
        for (var product in products) {
          String id = product['id'];
          quantities[id] = 0;
          controllers[id] = TextEditingController(text: '0');
          focusNodes[id] = FocusNode();
          focusNodes[id]!.addListener(() {
            if (focusNodes[id]!.hasFocus) {
              final controller = controllers[id];
              if (controller != null && controller.text == '0') {
                controller.text = '';
              }
            } else {
              final controller = controllers[id];
              if (controller != null && controller.text.isEmpty) {
                controller.text = '0';
                quantities[id] = 0;
              }
            }
          });
        }
        isLoading = false;
      });
    } catch (e) {
      print('Error fetching products: $e');
      setState(() => isLoading = false);
    }
  }

  double getTotalAmount() {
    double total = 0;
    for (var product in products) {
      String id = product['id'];
      int qty = quantities[id] ?? 0;
      double price = (product['price'] ?? 0).toDouble();
      total += qty * price;
    }
    return total;
  }

  int getTotalItems() {
    int total = 0;
    for (var qty in quantities.values) {
      total += qty;
    }
    return total;
  }

  Future<void> submitOrder() async {
    int totalItems = getTotalItems();
    if (totalItems == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one product'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select payment method'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final totalAmount = getTotalAmount();

      // 1. Create order
      final orderResponse = await supabase.from('orders').insert({
        'shopkeeper_id': widget.shopkeeperId,
        'delivery_date': selectedDeliveryDate.toIso8601String().split('T')[0],
        'total_amount': totalAmount,
        'payment_method': selectedPaymentMethod,
        'payment_status': selectedPaymentMethod == 'cash' ? 'pending' : 'pending',
        'status': 'pending',
      }).select();

      if (orderResponse.isEmpty) {
        throw Exception('Failed to create order');
      }

      final orderId = orderResponse[0]['id'];

      // 2. Create order items
      List<Map<String, dynamic>> orderItems = [];
      for (var product in products) {
        String id = product['id'];
        int qty = quantities[id] ?? 0;
        if (qty > 0) {
          orderItems.add({
            'order_id': orderId,
            'product_id': id,
            'quantity': qty,
            'price': product['price'],
            'total': qty * (product['price'] as num).toDouble(),
          });
        }
      }

      if (orderItems.isNotEmpty) {
        await supabase.from('order_items').insert(orderItems);
      }

      // 3. If payment is cash, update shopkeeper balance
      if (selectedPaymentMethod == 'cash') {
        await supabase.rpc('update_shopkeeper_balance', params: {
          'shopkeeper_id': widget.shopkeeperId,
          'amount': totalAmount,
        });
      }

      // Show success
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Order placed successfully! Total: ₹${totalAmount.toStringAsFixed(2)}',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() => isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Place Order'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () {
              int totalItems = getTotalItems();
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Order Summary'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Items: $totalItems'),
                      Text('Total Amount: ₹${getTotalAmount().toStringAsFixed(2)}'),
                      const Divider(),
                      ...products.where((p) => (quantities[p['id']] ?? 0) > 0).map(
                        (p) => Text(
                          '${p['name']} x ${quantities[p['id']]} = ₹${(quantities[p['id']]! * (p['price'] as num).toDouble()).toStringAsFixed(2)}',
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Delivery Date Picker
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.blue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Delivery Date',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${selectedDeliveryDate.day}/${selectedDeliveryDate.month}/${selectedDeliveryDate.year}',
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDeliveryDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 30),
                                ),
                              );
                              if (picked != null) {
                                setState(() {
                                  selectedDeliveryDate = picked;
                                });
                              }
                            },
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Payment Method
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Payment Method',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: RadioListTile<String>(
                                  title: const Text('Cash'),
                                  value: 'cash',
                                  groupValue: selectedPaymentMethod,
                                  onChanged: (value) {
                                    setState(() {
                                      selectedPaymentMethod = value;
                                    });
                                  },
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              Expanded(
                                child: RadioListTile<String>(
                                  title: const Text('Online'),
                                  value: 'online',
                                  groupValue: selectedPaymentMethod,
                                  onChanged: (value) {
                                    setState(() {
                                      selectedPaymentMethod = value;
                                    });
                                  },
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Products List
                  const Text(
                    'Products',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final product = products[index];
                        final String id = product['id'];
                        final int qty = quantities[id] ?? 0;
                        final double price =
                            (product['price'] ?? 0).toDouble();

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product['name'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        '₹${price.toStringAsFixed(2)} / ${product['unit']}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Minus Button
                                      IconButton(
                                        icon: const Icon(Icons.remove),
                                        color: Colors.white,
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.red.shade400,
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(36, 36),
                                          shape: const RoundedRectangleBorder(
                                            borderRadius: BorderRadius.only(
                                              topLeft: Radius.circular(8),
                                              bottomLeft: Radius.circular(8),
                                            ),
                                          ),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            int current = quantities[id] ?? 0;
                                            if (current > 0) {
                                              current -= 1;
                                              quantities[id] = current;
                                              controllers[id]?.text =
                                                  current.toString();
                                            }
                                          });
                                        },
                                      ),
                                      // Input Box
                                      Container(
                                        width: 60,
                                        height: 40,
                                        color: Colors.white,
                                        child: TextField(
                                          controller: controllers[id],
                                          focusNode: focusNodes[id],
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.center,
                                          decoration: const InputDecoration(
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          onChanged: (value) {
                                            if (value.isEmpty) {
                                              setState(() {
                                                quantities[id] = 0;
                                              });
                                              return;
                                            }
                                            String cleanValue = value
                                                .replaceAll(
                                                    RegExp(r'[^0-9]'), '');
                                            if (cleanValue != value) {
                                              controllers[id]!.text =
                                                  cleanValue;
                                              controllers[id]!.selection =
                                                  TextSelection.fromPosition(
                                                TextPosition(
                                                    offset: cleanValue.length),
                                              );
                                            }
                                            final int? parsed =
                                                int.tryParse(cleanValue);
                                            if (parsed != null && parsed >= 0) {
                                              setState(() {
                                                quantities[id] = parsed;
                                              });
                                            } else if (cleanValue.isEmpty) {
                                              setState(() {
                                                quantities[id] = 0;
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                      // Plus Button
                                      IconButton(
                                        icon: const Icon(Icons.add),
                                        color: Colors.white,
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.green.shade400,
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(36, 36),
                                          shape: const RoundedRectangleBorder(
                                            borderRadius: BorderRadius.only(
                                              topRight: Radius.circular(8),
                                              bottomRight: Radius.circular(8),
                                            ),
                                          ),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            int current = quantities[id] ?? 0;
                                            current += 1;
                                            quantities[id] = current;
                                            controllers[id]?.text =
                                                current.toString();
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Submit Button
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: isSaving ? null : submitOrder,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              'Place Order - ₹${getTotalAmount().toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 18),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}