import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // for Clipboard
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:barcode/barcode.dart';

class ShopDeliveryFlowScreen extends StatefulWidget {
  final Map<String, dynamic> delivery;
  final String driverId;
  final String? preSelectedShopId;

  const ShopDeliveryFlowScreen({
    super.key,
    required this.delivery,
    required this.driverId,
    this.preSelectedShopId,
  });

  @override
  State<ShopDeliveryFlowScreen> createState() => _ShopDeliveryFlowScreenState();
}

class _ShopDeliveryFlowScreenState extends State<ShopDeliveryFlowScreen> {
  final supabase = Supabase.instance.client;

  // ---- GPS ----
  Position? _currentPosition;
  bool _isLoadingGps = false;
  String? _gpsError;
  static const double _mockLat = 19.0760;
  static const double _mockLng = 72.8777;

  // ---- Shopkeepers ----
  List<Map<String, dynamic>> _allShops = [];
  List<Map<String, dynamic>> _nearbyShops = [];
  bool _isSearching = false;
  String? _selectedShopkeeperId;
  final TextEditingController _searchController = TextEditingController();

  // ---- New Shop Form ----
  bool _isCreatingNew = false;
  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _ownerNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _gstController = TextEditingController();
  String? _newShopBarcodeId;

  // ---- Products ----
  List<Map<String, dynamic>> _products = [];
  Map<String, TextEditingController> _orderControllers = {};
  Map<String, TextEditingController> _returnControllers = {};
  bool _isLoadingProducts = true;

  // ---- Multi‑Step Flow ----
  int _currentStep = 0; // 0: Order, 1: Returns question, 2: Return entry, 3: Confirm
  bool _isSaving = false;
  List<Map<String, dynamic>> _orderItems = [];
  List<Map<String, dynamic>> _returnItems = [];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _fetchProducts();
    _fetchAllShops().then((_) {
      if (widget.preSelectedShopId != null) {
        _selectShopById(widget.preSelectedShopId!);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _shopNameController.dispose();
    _ownerNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _gstController.dispose();
    for (var c in _orderControllers.values) c.dispose();
    for (var c in _returnControllers.values) c.dispose();
    super.dispose();
  }

  // ---------- GPS ----------
  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingGps = true);
    try {
      if (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        setState(() {
          _currentPosition = Position(
            latitude: _mockLat,
            longitude: _mockLng,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            heading: 0,
            speed: 0,
            speedAccuracy: 0,
            altitudeAccuracy: 0,
            headingAccuracy: 0,
          );
          _gpsError = null;
          _isLoadingGps = false;
        });
        _filterNearbyShops();
        return;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _gpsError = 'Location services are disabled.';
          _isLoadingGps = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _gpsError = 'Location permission denied.';
            _isLoadingGps = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _gpsError = 'Location permission permanently denied.';
          _isLoadingGps = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = position;
        _gpsError = null;
        _isLoadingGps = false;
      });
      _filterNearbyShops();
    } catch (e) {
      setState(() {
        _gpsError = 'Error getting location: $e';
        _isLoadingGps = false;
      });
    }
  }

  double _toRadians(double deg) => deg * pi / 180;

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371;
    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon2 - lon1);
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  // ---------- Shopkeepers ----------
  Future<void> _fetchAllShops() async {
    try {
      final data = await supabase.from('shopkeepers').select('*').order('shop_name');
      setState(() {
        _allShops = List<Map<String, dynamic>>.from(data);
      });
      _filterNearbyShops();
    } catch (e) {
      print('⚠️ Error fetching shops: $e');
    }
  }

  void _filterNearbyShops() {
    if (_currentPosition == null) {
      setState(() => _nearbyShops = []);
      return;
    }
    const double radiusKm = 5.0;
    final filtered = _allShops.where((shop) {
      final lat = shop['latitude'] as double?;
      final lng = shop['longitude'] as double?;
      if (lat == null || lng == null) return false;
      final distance = _calculateDistance(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        lat,
        lng,
      );
      return distance <= radiusKm;
    }).toList();
    filtered.sort((a, b) {
      final d1 = _calculateDistance(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        a['latitude'] as double,
        a['longitude'] as double,
      );
      final d2 = _calculateDistance(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        b['latitude'] as double,
        b['longitude'] as double,
      );
      return d1.compareTo(d2);
    });
    setState(() {
      _nearbyShops = filtered;
    });
  }

  Future<void> _searchShopkeepers() async {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filterNearbyShops();
      return;
    }
    setState(() => _isSearching = true);
    try {
      final data = await supabase
          .from('shopkeepers')
          .select('*')
          .or('shop_name.ilike.%$query%,owner_name.ilike.%$query%,phone.ilike.%$query%')
          .order('shop_name');
      setState(() {
        _nearbyShops = List<Map<String, dynamic>>.from(data);
        _isSearching = false;
      });
    } catch (e) {
      print('❌ Search error: $e');
      setState(() => _isSearching = false);
    }
  }

  void _selectShopkeeper(Map<String, dynamic> shop) {
    setState(() {
      _selectedShopkeeperId = shop['id'];
      _isCreatingNew = false;
      _resetFlow();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Selected ${shop['shop_name']}'), backgroundColor: Colors.green),
    );
  }

  Future<void> _selectShopById(String shopId) async {
    try {
      final shop = await supabase
          .from('shopkeepers')
          .select('*')
          .eq('id', shopId)
          .maybeSingle();
      if (shop != null) {
        setState(() {
          _selectedShopkeeperId = shop['id'];
          _searchController.text = shop['shop_name'] ?? '';
          _resetFlow();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Selected ${shop['shop_name']}'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shop not found'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      print('Error selecting shop: $e');
    }
  }

  void _startCreateNew() {
    setState(() {
      _isCreatingNew = true;
      _selectedShopkeeperId = null;
      _shopNameController.clear();
      _ownerNameController.clear();
      _phoneController.clear();
      _addressController.clear();
      _gstController.clear();
      _newShopBarcodeId = null;
      _resetFlow();
    });
  }

  Future<void> _createShopkeeper() async {
    if (_shopNameController.text.isEmpty ||
        _ownerNameController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _addressController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields'), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      final barcodeId = 'SHOP-${_phoneController.text.trim()}-${DateTime.now().millisecondsSinceEpoch.toString().substring(8, 12)}';

      final newShop = {
        'shop_name': _shopNameController.text.trim(),
        'owner_name': _ownerNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'gst_number': _gstController.text.trim().isEmpty ? null : _gstController.text.trim(),
        'barcode_id': barcodeId,
        'created_by': widget.driverId,
        'balance': 0,
        'latitude': _currentPosition?.latitude,
        'longitude': _currentPosition?.longitude,
      };

      final response = await supabase
          .from('shopkeepers')
          .insert(newShop)
          .select()
          .maybeSingle();

      if (response == null) throw Exception('Failed to create shopkeeper');

      setState(() {
        _newShopBarcodeId = response['barcode_id'];
        _selectedShopkeeperId = response['id'];
        _isCreatingNew = false;
        _allShops.add(response);
        _filterNearbyShops();
        _resetFlow();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Shopkeeper created!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ---------- Products ----------
  Future<void> _fetchProducts() async {
    setState(() => _isLoadingProducts = true);
    try {
      final data = await supabase.from('products').select('*').order('name');
      setState(() {
        _products = List<Map<String, dynamic>>.from(data);
        for (var p in _products) {
          final id = p['id'];
          _orderControllers[id] = TextEditingController(text: '0');
          _returnControllers[id] = TextEditingController(text: '0');
        }
        _isLoadingProducts = false;
      });
    } catch (e) {
      print('❌ Error loading products: $e');
      setState(() => _isLoadingProducts = false);
    }
  }

  // ---------- Multi‑Step Flow Methods ----------
  void _resetFlow() {
    setState(() {
      _currentStep = 0;
      _orderItems = [];
      _returnItems = [];
    });
    for (var p in _products) {
      final id = p['id'];
      _orderControllers[id]?.text = '0';
      _returnControllers[id]?.text = '0';
    }
  }

  void _proceedToReturns() {
    final items = <Map<String, dynamic>>[];
    for (var p in _products) {
      final id = p['id'];
      final qty = int.tryParse(_orderControllers[id]?.text.trim() ?? '0') ?? 0;
      if (qty > 0) {
        items.add({
          'product_id': id,
          'quantity': qty,
          'price': p['price'],
          'name': p['name'],
        });
      }
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one order item'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() {
      _orderItems = items;
      _currentStep = 1;
    });
  }

  void _handleReturns(bool hasReturns) {
    if (hasReturns) {
      setState(() => _currentStep = 2);
    } else {
      setState(() => _currentStep = 3);
    }
  }

  void _proceedToSummary() {
    final items = <Map<String, dynamic>>[];
    for (var p in _products) {
      final id = p['id'];
      final qty = int.tryParse(_returnControllers[id]?.text.trim() ?? '0') ?? 0;
      if (qty > 0) {
        items.add({
          'product_id': id,
          'quantity': qty,
        });
      }
    }
    setState(() {
      _returnItems = items;
      _currentStep = 3;
    });
  }
Future<void> _deductMasterStock(List<Map<String, dynamic>> orderItems) async {
  final today = DateTime.now().toLocal().toString().split(' ')[0];
  print('🔍 Deducing master stock for today: $today');
  for (var item in orderItems) {
    final productId = item['product_id'];
    final productName = item['name'];
    final qty = item['quantity'] as int;
    print('🔍 Deducting $qty of $productName (ID: $productId)');
    final masterRecord = await supabase
        .from('master_stock')
        .select('id, remaining_quantity')
        .eq('product_id', productId)
        .eq('date', today)
        .maybeSingle();
    if (masterRecord == null) {
      print('❌ No master stock found for $productName (ID: $productId)');
      throw Exception('Master stock not found for product $productName');
    }
    final current = masterRecord['remaining_quantity'] as int;
    final newStock = current - qty;
    if (newStock < 0) throw Exception('Insufficient master stock for $productName');
    print('✅ Updating master stock: $current -> $newStock');
    await supabase
        .from('master_stock')
        .update({'remaining_quantity': newStock})
        .eq('id', masterRecord['id']);
        // After the update
final afterUpdate = await supabase
    .from('master_stock')
    .select('remaining_quantity')
    .eq('id', masterRecord['id'])
    .maybeSingle();
print('🔍 After update, remaining_quantity = ${afterUpdate?['remaining_quantity']}');
  }
}
Future<void> _addReturnsToMasterStock(List<Map<String, dynamic>> returnItems) async {
  final today = DateTime.now().toLocal().toString().split(' ')[0];
  for (var item in returnItems) {
    final productId = item['product_id'];
    final qty = item['quantity'] as int;
    final masterRecord = await supabase
        .from('master_stock')
        .select('id, remaining_quantity')
        .eq('product_id', productId)
        .eq('date', today)
        .maybeSingle();
    if (masterRecord != null) {
      final currentRemaining = masterRecord['remaining_quantity'] as int;
      final newRemaining = currentRemaining + qty;
      await supabase
          .from('master_stock')
          .update({'remaining_quantity': newRemaining})
          .eq('id', masterRecord['id']);
    } else {
      // If no master stock exists, we can create one with 0 initial and add returns (but better to throw)
      throw Exception('Master stock not found for return product. Please contact admin.');
    }
  }
}

  // ---------- Receipt Dialog ----------
  Future<void> _showReceiptDialog() async {
    // _selectedShopkeeperId is guaranteed non-null here
    final shop = await supabase
        .from('shopkeepers')
        .select('shop_name, phone, address')
        .eq('id', _selectedShopkeeperId!) // FIXED: added !
        .maybeSingle();

    final shopName = shop?['shop_name'] ?? 'Unknown Shop';
    final shopPhone = shop?['phone'] ?? '';
    final shopAddress = shop?['address'] ?? '';

    double orderTotal = 0;
    double returnTotal = 0;
    for (var item in _orderItems) {
      orderTotal += (item['price'] as num) * (item['quantity'] as int);
    }
    for (var item in _returnItems) {
      final product = _products.firstWhere(
        (p) => p['id'] == item['product_id'],
        orElse: () => {'price': 0},
      );
      returnTotal += (product['price'] as num) * (item['quantity'] as int);
    }

    final netAmount = orderTotal - returnTotal;

    final now = DateTime.now().toLocal();
    final receipt = '''
🧾 *DELIVERY RECEIPT*
─────────────────────────
Shop: $shopName
Phone: $shopPhone
Date: ${now.toLocal().toString().split(' ')[0]}
Time: ${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}
─────────────────────────
*ORDER ITEMS*
${_orderItems.map((item) => '  ${item['name']} × ${item['quantity']} = ₹${(item['price'] as num) * (item['quantity'] as int)}').join('\n')}
${_orderItems.isEmpty ? '  (none)' : ''}
─────────────────────────
*RETURN ITEMS*
${_returnItems.map((item) {
  final product = _products.firstWhere(
    (p) => p['id'] == item['product_id'],
    orElse: () => {'name': 'Unknown', 'price': 0},
  );
  return '  ${product['name']} × ${item['quantity']}';
}).join('\n')}
${_returnItems.isEmpty ? '  (none)' : ''}
─────────────────────────
*ORDER TOTAL: ₹${orderTotal.toStringAsFixed(2)}*
*RETURN TOTAL: ₹${returnTotal.toStringAsFixed(2)}*
*NET AMOUNT DUE: ₹${netAmount.toStringAsFixed(2)}*
─────────────────────────
Thank you for your business!
''';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Delivery Receipt'),
        content: SingleChildScrollView(
          child: Text(
            receipt,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: receipt));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Receipt copied to clipboard!'), backgroundColor: Colors.green),
              );
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  // ---------- Confirm Delivery ----------
 Future<void> _finalConfirmDelivery() async {
  if (_selectedShopkeeperId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please select or create a shopkeeper'), backgroundColor: Colors.orange),
    );
    return;
  }

  if (_orderItems.isEmpty && _returnItems.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No order or return items to confirm'), backgroundColor: Colors.orange),
    );
    return;
  }

  setState(() => _isSaving = true);

  try {
    // 1. Deduct master stock for orders (if any)
    if (_orderItems.isNotEmpty) {
      await _deductMasterStock(_orderItems);
    }

    // 2. Deduct driver stock for orders (as before)
    if (_orderItems.isNotEmpty) {
      final today = DateTime.now().toLocal().toString().split(' ')[0];
      for (var item in _orderItems) {
        final productId = item['product_id'];
        final qty = item['quantity'] as int;
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
          if (newStock < 0) throw Exception('Insufficient driver stock');
          await supabase
              .from('driver_stock')
              .update({'quantity_loaded': newStock})
              .eq('id', stockRecord['id']);
        } else {
          throw Exception('Driver stock not found');
        }
      }
    }

    // 3. Add returns to driver stock (as before)
    if (_returnItems.isNotEmpty) {
      final today = DateTime.now().toLocal().toString().split(' ')[0];
      for (var item in _returnItems) {
        final productId = item['product_id'];
        final qty = item['quantity'] as int;
        final stockRecord = await supabase
            .from('driver_stock')
            .select('id, quantity_loaded')
            .eq('driver_id', widget.driverId)
            .eq('product_id', productId)
            .eq('date', today)
            .maybeSingle();
        if (stockRecord != null) {
          final currentStock = stockRecord['quantity_loaded'] as int;
          final newStock = currentStock + qty;
          await supabase
              .from('driver_stock')
              .update({'quantity_loaded': newStock})
              .eq('id', stockRecord['id']);
        } else {
          await supabase.from('driver_stock').insert({
            'driver_id': widget.driverId,
            'product_id': productId,
            'quantity_loaded': qty,
            'date': today,
          });
        }
      }
    }

    // 4. Add returns to master stock (new)
    if (_returnItems.isNotEmpty) {
      await _addReturnsToMasterStock(_returnItems);
    }

    // 5. Update or insert delivery record
    final deliveryData = {
      'status': 'delivered',
      'shopkeeper_id': _selectedShopkeeperId,
      'items': _orderItems,
      'returns': _returnItems,
      'delivered_at': DateTime.now().toUtc().toIso8601String(),
    };

    final bool isNewDelivery = widget.delivery['id'] == 'new';
    if (isNewDelivery) {
      final shopName = (await supabase
          .from('shopkeepers')
          .select('shop_name')
          .eq('id', _selectedShopkeeperId!)
          .maybeSingle())?['shop_name'] ?? 'Unknown Shop';
      final address = (await supabase
          .from('shopkeepers')
          .select('address')
          .eq('id', _selectedShopkeeperId!)
          .maybeSingle())?['address'] ?? '';
      final newDeliveryData = {
        ...deliveryData,
        'driver_id': widget.driverId,
        'scheduled_date': DateTime.now().toLocal().toString().split(' ')[0],
        'shop_name': shopName,
        'address': address,
      };
      await supabase.from('deliveries').insert(newDeliveryData);
    } else {
      await supabase
          .from('deliveries')
          .update(deliveryData)
          .eq('id', widget.delivery['id']);
    }

    // 6. Show receipt
    await _showReceiptDialog();

    // 7. Pop to dashboard
    Navigator.pop(context, true);
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
    );
  } finally {
    setState(() => _isSaving = false);
  }
}
  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop Delivery'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (_selectedShopkeeperId != null || _isCreatingNew) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _resetFlow,
              tooltip: 'Reset order',
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- GPS ----
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      _currentPosition != null ? Icons.gps_fixed : Icons.gps_off,
                      color: _currentPosition != null ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _isLoadingGps
                          ? const SizedBox(height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(
                              _gpsError ?? (_currentPosition != null
                                  ? '📍 ${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}'
                                  : 'GPS not locked'),
                              style: TextStyle(color: _gpsError != null ? Colors.red : Colors.black),
                            ),
                    ),
                    if (_gpsError != null || _currentPosition == null)
                      TextButton(
                        onPressed: _getCurrentLocation,
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ---- Shopkeeper ----
            const Text('Shopkeeper', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            if (!_isCreatingNew) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search by name, phone...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onSubmitted: (_) => _searchShopkeepers(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _searchShopkeepers,
                    child: const Text('Search'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Column(
                children: [
                  if (_nearbyShops.isNotEmpty)
                    ..._nearbyShops.map((shop) {
                      final isSelected = shop['id'] == _selectedShopkeeperId;
                      final distance = _currentPosition != null && shop['latitude'] != null && shop['longitude'] != null
                          ? _calculateDistance(
                              _currentPosition!.latitude,
                              _currentPosition!.longitude,
                              shop['latitude'] as double,
                              shop['longitude'] as double,
                            ).toStringAsFixed(1)
                          : '?';
                      return Card(
                        color: isSelected ? Colors.blue.shade50 : null,
                        child: ListTile(
                          title: Text(shop['shop_name'] ?? 'Unknown'),
                          subtitle: Text('${shop['phone']} • ${shop['address']} • ${distance}km'),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => _selectShopkeeper(shop),
                        ),
                      );
                    }).toList(),
                  if (_nearbyShops.isEmpty && _searchController.text.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text('No nearby shops found.', style: TextStyle(color: Colors.grey)),
                    ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: _startCreateNew,
                      icon: const Icon(Icons.add),
                      label: const Text('Create New Shopkeeper'),
                    ),
                  ),
                ],
              ),
            ],

            if (_isCreatingNew) ...[
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('New Shopkeeper', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _shopNameController,
                        decoration: const InputDecoration(labelText: 'Shop Name *'),
                      ),
                      TextField(
                        controller: _ownerNameController,
                        decoration: const InputDecoration(labelText: 'Owner Name *'),
                      ),
                      TextField(
                        controller: _phoneController,
                        decoration: const InputDecoration(labelText: 'Phone *'),
                        keyboardType: TextInputType.phone,
                      ),
                      TextField(
                        controller: _addressController,
                        decoration: const InputDecoration(labelText: 'Address *'),
                      ),
                      TextField(
                        controller: _gstController,
                        decoration: const InputDecoration(labelText: 'GST Number (optional)'),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _createShopkeeper,
                              icon: const Icon(Icons.save),
                              label: const Text('Create Shop'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => setState(() => _isCreatingNew = false),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                      if (_newShopBarcodeId != null) ...[
                        const SizedBox(height: 16),
                        const Text('QR Code for this shop:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        BarcodeWidget(
                          barcode: Barcode.qrCode(),
                          data: _newShopBarcodeId!,
                          width: 120,
                          height: 120,
                        ),
                        Text(_newShopBarcodeId!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ---- Multi‑Step Order & Returns ----
            if (_selectedShopkeeperId != null || _isCreatingNew) ...[
              // Step indicator
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    _buildStepIndicator('Order', _currentStep >= 0),
                    _buildStepConnector(_currentStep > 0),
                    _buildStepIndicator('Returns?', _currentStep >= 1),
                    _buildStepConnector(_currentStep > 1),
                    _buildStepIndicator('Confirm', _currentStep >= 3),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Step 0: Order Entry
              if (_currentStep == 0) ...[
                const Text('Enter Order Quantities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_isLoadingProducts)
                  const Center(child: CircularProgressIndicator())
                else
                  ..._products.map((p) {
                    final id = p['id'];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text('Unit: ${p['unit']}  •  Price: ₹${p['price']}'),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: TextField(
                                controller: _orderControllers[id]!,
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton(
                    onPressed: _proceedToReturns,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Proceed to Returns'),
                  ),
                ),
              ],

              // Step 1: Returns Question
              if (_currentStep == 1) ...[
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text(
                          'Any returns from this shop?',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => _handleReturns(true),
                              icon: const Icon(Icons.check),
                              label: const Text('Yes'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(100, 45),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _handleReturns(false),
                              icon: const Icon(Icons.close),
                              label: const Text('No'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(100, 45),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Step 2: Return Entry
              if (_currentStep == 2) ...[
                const Text('Enter Return Quantities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_isLoadingProducts)
                  const Center(child: CircularProgressIndicator())
                else
                  ..._products.map((p) {
                    final id = p['id'];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text('Unit: ${p['unit']}'),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: TextField(
                                controller: _returnControllers[id]!,
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton(
                    onPressed: _proceedToSummary,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Confirm Returns & Proceed'),
                  ),
                ),
              ],

              // Step 3: Summary & Confirm
              if (_currentStep == 3) ...[
                const Text('Order Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_orderItems.isEmpty && _returnItems.isEmpty)
                  const Text('No items to confirm.', style: TextStyle(color: Colors.grey))
                else ...[
                  if (_orderItems.isNotEmpty) ...[
                    const Text('Order Items:', style: TextStyle(fontWeight: FontWeight.w600)),
                    ..._orderItems.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('• ${item['name']} x ${item['quantity']} = ₹${(item['price'] as num) * (item['quantity'] as int)}'),
                    )).toList(),
                    const SizedBox(height: 8),
                  ],
                  if (_returnItems.isNotEmpty) ...[
                    const Text('Return Items:', style: TextStyle(fontWeight: FontWeight.w600)),
                    ..._returnItems.map((item) {
                      final product = _products.firstWhere(
                        (p) => p['id'] == item['product_id'],
                        orElse: () => {'name': 'Unknown'},
                      );
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• ${product['name']} x ${item['quantity']}'),
                      );
                    }).toList(),
                  ],
                  const Divider(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _finalConfirmDelivery,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Confirm Delivery & Update Stock', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  // Helper for step indicators
  Widget _buildStepIndicator(String label, bool active) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: active ? Colors.blue : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.grey.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepConnector(bool active) {
    return Expanded(
      flex: 1,
      child: Container(
        height: 2,
        color: active ? Colors.blue : Colors.grey.shade300,
        margin: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}