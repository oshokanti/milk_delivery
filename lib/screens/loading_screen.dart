import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:milk_delivery/screens/dashboard_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  final supabase = Supabase.instance.client;

  bool isLoading = true;
  bool isSaving = false;

  List<Map<String, dynamic>> vehicles = [];
  List<Map<String, dynamic>> products = [];
  Map<String, int> stockQuantities = {};
  Map<String, TextEditingController> quantityControllers = {};
  Map<String, FocusNode> focusNodes = {};
  String? selectedVehicleId;

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  @override
  void dispose() {
    for (var controller in quantityControllers.values) {
      controller.dispose();
    }
    for (var focusNode in focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> fetchData() async {
    setState(() => isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final vehicleData = await supabase
          .from('vehicles')
          .select()
          .eq('driver_id', user.id);

      final productData = await supabase
          .from('products')
          .select();

      setState(() {
        vehicles = List<Map<String, dynamic>>.from(vehicleData);
        products = List<Map<String, dynamic>>.from(productData);

        if (vehicles.length == 1) {
          selectedVehicleId = vehicles[0]['id'];
        }

        stockQuantities = {};
        quantityControllers = {};
        focusNodes = {};
        for (var product in products) {
          String productId = product['id'];
          stockQuantities[productId] = 0;
          quantityControllers[productId] = TextEditingController(text: '0');
          focusNodes[productId] = FocusNode();
          
          focusNodes[productId]!.addListener(() {
            if (focusNodes[productId]!.hasFocus) {
              final controller = quantityControllers[productId];
              if (controller != null && controller.text == '0') {
                controller.text = '';
              }
            } else {
              final controller = quantityControllers[productId];
              if (controller != null && controller.text.isEmpty) {
                controller.text = '0';
                stockQuantities[productId] = 0;
              }
            }
          });
        }

        isLoading = false;
      });
    } catch (e) {
      print('Error: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> saveLoadingSession() async {
    if (selectedVehicleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a vehicle')),
      );
      return;
    }

    bool hasStock = stockQuantities.values.any((q) => q > 0);
    if (!hasStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one product')),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final user = supabase.auth.currentUser;

      Map<String, dynamic> loadItems = {};
      stockQuantities.forEach((key, value) {
        if (value > 0) loadItems[key] = value;
      });

      await supabase.from('loading_sessions').insert({
        'driver_id': user!.id,
        'vehicle_id': selectedVehicleId,
        'load_items': loadItems,
        'status': 'active',
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }

    setState(() => isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Start Day - Load Stock'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await supabase.auth.signOut();
              Navigator.pushReplacementNamed(context, '/');
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
                  Text('Driver: ${user?.email ?? ''}'),
                  const SizedBox(height: 16),
                  const Text(
                    'Select Vehicle',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedVehicleId,
                    hint: const Text('Choose your vehicle'),
                    isExpanded: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: vehicles.map((vehicle) {
                      return DropdownMenuItem<String>(
                        value: vehicle['id'],
                        child: Text(
                          '${vehicle['vehicle_type']} - ${vehicle['vehicle_number']}',
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => selectedVehicleId = value);
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Load Stock',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter quantity for each product',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final product = products[index];
                        final String productId = product['id'];
                        final int quantity = stockQuantities[productId] ?? 0;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center, // ✅ Vertical center alignment
                              children: [
                                // Product Name & Unit
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product['name'] ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        'Unit: ${product['unit'] ?? ''}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Quantity Controls - all vertically centered
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                      width: 1,
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
                                            int current =
                                                stockQuantities[productId] ?? 0;
                                            if (current > 0) {
                                              current -= 1;
                                              stockQuantities[productId] =
                                                  current;
                                              quantityControllers[productId]
                                                  ?.text = current.toString();
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
                                          controller:
                                              quantityControllers[productId],
                                          focusNode: focusNodes[productId],
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
                                                stockQuantities[productId] = 0;
                                              });
                                              return;
                                            }
                                            String cleanValue = value.replaceAll(
                                                RegExp(r'[^0-9]'), '');
                                            if (cleanValue != value) {
                                              quantityControllers[productId]!
                                                  .text = cleanValue;
                                              quantityControllers[productId]!
                                                  .selection = TextSelection.fromPosition(
                                                TextPosition(
                                                    offset: cleanValue.length),
                                              );
                                            }
                                            final int? parsed =
                                                int.tryParse(cleanValue);
                                            if (parsed != null && parsed >= 0) {
                                              setState(() {
                                                stockQuantities[productId] =
                                                    parsed;
                                              });
                                            } else if (cleanValue.isEmpty) {
                                              setState(() {
                                                stockQuantities[productId] = 0;
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
                                            int current =
                                                stockQuantities[productId] ?? 0;
                                            current += 1;
                                            stockQuantities[productId] = current;
                                            quantityControllers[productId]
                                                ?.text = current.toString();
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
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: isSaving ? null : saveLoadingSession,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Start Delivery',
                              style: TextStyle(fontSize: 18),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}