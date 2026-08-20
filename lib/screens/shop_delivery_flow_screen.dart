import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
  double _shopkeeperBalance = 0.0;
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
  int _currentStep = 0;
  bool _isSaving = false;
  List<Map<String, dynamic>> _orderItems = [];
  List<Map<String, dynamic>> _returnItems = [];

  // ---- Voice Order ----
  bool _isListening = false;
  bool _isProcessingVoice = false;

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
        if (mounted) {
          setState(() {
            _gpsError = 'Location services are disabled.';
            _isLoadingGps = false;
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _gpsError = 'Location permission denied.';
              _isLoadingGps = false;
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _gpsError = 'Location permission permanently denied.';
            _isLoadingGps = false;
          });
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _gpsError = null;
          _isLoadingGps = false;
        });
      }
      _filterNearbyShops();
    } catch (e) {
      if (mounted) {
        setState(() {
          _gpsError = 'Error getting location: $e';
          _isLoadingGps = false;
        });
      }
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
      if (mounted) {
        setState(() {
          _allShops = List<Map<String, dynamic>>.from(data);
        });
      }
      _filterNearbyShops();
    } catch (e) {
      print('⚠️ Error fetching shops: $e');
    }
  }

  void _filterNearbyShops() {
    if (_currentPosition == null) {
      if (mounted) {
        setState(() => _nearbyShops = []);
      }
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
    if (mounted) {
      setState(() {
        _nearbyShops = filtered;
      });
    }
  }

  Future<void> _searchShopkeepers() async {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filterNearbyShops();
      return;
    }
    if (mounted) {
      setState(() => _isSearching = true);
    }
    try {
      final data = await supabase
          .from('shopkeepers')
          .select('*')
          .or('shop_name.ilike.%$query%,owner_name.ilike.%$query%,phone.ilike.%$query%')
          .order('shop_name');
      if (mounted) {
        setState(() {
          _nearbyShops = List<Map<String, dynamic>>.from(data);
          _isSearching = false;
        });
      }
    } catch (e) {
      print('❌ Search error: $e');
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _selectShopkeeper(Map<String, dynamic> shop) {
    double balance = (shop['balance'] ?? 0).toDouble();
    if (mounted) {
      setState(() {
        _selectedShopkeeperId = shop['id'];
        _shopkeeperBalance = balance;
        _isCreatingNew = false;
        _resetFlow();
      });
    }
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
        double balance = (shop['balance'] ?? 0).toDouble();
        if (mounted) {
          setState(() {
            _selectedShopkeeperId = shop['id'];
            _shopkeeperBalance = balance;
            _searchController.text = shop['shop_name'] ?? '';
            _resetFlow();
          });
        }
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
    if (mounted) {
      setState(() {
        _isCreatingNew = true;
        _selectedShopkeeperId = null;
        _shopkeeperBalance = 0.0;
        _shopNameController.clear();
        _ownerNameController.clear();
        _phoneController.clear();
        _addressController.clear();
        _gstController.clear();
        _newShopBarcodeId = null;
        _resetFlow();
      });
    }
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

      if (mounted) {
        setState(() {
          _newShopBarcodeId = response['barcode_id'];
          _selectedShopkeeperId = response['id'];
          _shopkeeperBalance = 0.0;
          _isCreatingNew = false;
          _allShops.add(response);
          _filterNearbyShops();
          _resetFlow();
        });
      }

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
    if (mounted) {
      setState(() => _isLoadingProducts = true);
    }
    try {
      final data = await supabase.from('products').select('*').order('name');
      if (mounted) {
        setState(() {
          _products = List<Map<String, dynamic>>.from(data);
          for (var p in _products) {
            final id = p['id'];
            _orderControllers[id] = TextEditingController(text: '0');
            _returnControllers[id] = TextEditingController(text: '0');
          }
          _isLoadingProducts = false;
        });
      }
    } catch (e) {
      print('❌ Error loading products: $e');
      if (mounted) {
        setState(() => _isLoadingProducts = false);
      }
    }
  }

  // ---------- Multi‑Step Flow ----------
  void _resetFlow() {
    if (mounted) {
      setState(() {
        _currentStep = 0;
        _orderItems = [];
        _returnItems = [];
      });
    }
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
    if (mounted) {
      setState(() {
        _orderItems = items;
        _currentStep = 1;
      });
    }
  }

  void _handleReturns(bool hasReturns) {
    if (mounted) {
      setState(() {
        if (hasReturns) {
          _currentStep = 2;
        } else {
          _currentStep = 3;
        }
      });
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
    if (mounted) {
      setState(() {
        _returnItems = items;
        _currentStep = 3;
      });
    }
  }

  // ---------- Voice Order with AI ----------
  Future<void> _voiceOrder() async {
    if (_isProcessingVoice) return;

    final speech = stt.SpeechToText();
    bool available = await speech.initialize(
      onStatus: (status) {
        if (status == 'notListening' && _isListening) {
          setState(() => _isListening = false);
        }
      },
      onError: (error) => print('Speech error: $error'),
    );
    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition not available'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isListening = true);
    String? spokenText;
    await speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          spokenText = result.recognizedWords;
          setState(() => _isListening = false);
        }
      },
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 3),
    );

    if (spokenText == null || spokenText!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No speech detected'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isProcessingVoice = true);
    try {
      final parsed = await _parseOrderWithAI(spokenText!);
      int filledCount = 0;
      for (var entry in parsed.entries) {
        final productName = entry.key;
        final qty = entry.value;
        final product = _products.firstWhere(
          (p) => p['name'] == productName,
          orElse: () => {},
        );
        if (product.isNotEmpty) {
          _orderControllers[product['id']]?.text = qty.toString();
          filledCount++;
        }
      }
      if (filledCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not match any product from your speech. Please try again.'), backgroundColor: Colors.orange),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Filled $filledCount product(s) from voice'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isProcessingVoice = false);
    }
  }

  Future<Map<String, int>> _parseOrderWithAI(String spokenText) async {
    final apiKey = dotenv.env['DEEPSEEK_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Missing DeepSeek API key. Please add DEEPSEEK_API_KEY to .env');
    }

    final productNames = _products.map((p) => p['name']).join(', ');

    final prompt = '''
You are a helpful assistant that extracts product quantities from order requests.

Product list: $productNames

Extract the quantities from the following spoken order and return ONLY a JSON object with product names as keys and quantities as integers.
Example: {"Plain Chaach": 5, "Paneer 200G": 3}

Do not include any extra text or explanation.
Spoken order: "$spokenText"
''';

    final response = await http.post(
      Uri.parse('https://api.deepseek.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'deepseek-chat',
        'messages': [
          {'role': 'system', 'content': 'You are a precise JSON extractor.'},
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.1,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('AI API error: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);
    final content = data['choices'][0]['message']['content'];
    try {
      final json = jsonDecode(content);
      final Map<String, int> result = {};
      json.forEach((key, value) {
        if (value is int) {
          result[key] = value;
        } else if (value is String) {
          result[key] = int.tryParse(value) ?? 0;
        }
      });
      return result;
    } catch (e) {
      throw Exception('Failed to parse AI response: $content');
    }
  }

  // ---------- Payment Collection ----------
  Future<void> _collectPayment({double? defaultAmount}) async {
    if (defaultAmount == null || defaultAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No amount due.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final totalPayable = _shopkeeperBalance;
    final TextEditingController amountController = TextEditingController(
      text: totalPayable.toStringAsFixed(2),
    );
    String selectedMethod = 'cash';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Collect Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    flex: 2,
                    child: Text('Total Outstanding:'),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      '₹${totalPayable.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                  labelText: 'Payment Mode',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount Received (0 for no payment)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text.trim()) ?? 0;
                if (amount < 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Amount cannot be negative'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                if (amount > totalPayable) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Amount exceeds total outstanding'), backgroundColor: Colors.orange),
                  );
                  return;
                }

                if (amount > 0) {
                  try {
                    await supabase.from('transactions').insert({
                      'shopkeeper_id': _selectedShopkeeperId!,
                      'amount': amount,
                      'method': selectedMethod,
                      'collected_by': widget.driverId,
                      'collected_at': DateTime.now().toUtc().toIso8601String(),
                    });
                    final newBalance = _shopkeeperBalance - amount;
                    await supabase
                        .from('shopkeepers')
                        .update({'balance': newBalance})
                        .eq('id', _selectedShopkeeperId!);
                    if (mounted) {
                      setState(() {
                        _shopkeeperBalance = newBalance;
                      });
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                    return;
                  }
                } else {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('No payment collected. Balance updated.')),
                  );
                }

                Navigator.pop(ctx);
                print('💳 Payment dialog popped, amount: $amount, method: $selectedMethod');

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    print('📢 Calling _showFinalReceipt via WidgetsBinding...');
                    _showFinalReceipt(amount: amount, method: selectedMethod);
                  } else {
                    print('❌ Widget not mounted, cannot show final receipt');
                  }
                });
              },
              child: const Text('Confirm Payment'),
            ),
          ],
        );
      },
    );
  }

  // ---------- Desktop Printing ----------
  Future<void> _printReceiptDesktop(String receiptText) async {
    try {
      pw.Font? ttf;
      try {
        final fontData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
        ttf = pw.Font.ttf(fontData);
        print('✅ Unicode font loaded successfully');
      } catch (e) {
        print('⚠️ Unicode font not found, using default font');
        ttf = null;
      }

      final cleanText = receiptText
          .replaceAll('*', '')
          .replaceAll('_', '')
          .replaceAll(RegExp(r'[─━]'), '-')
          .replaceAll('─────────────────────────', '------------------------');

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          margin: const pw.EdgeInsets.all(10),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('MEDHYA FARM',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, font: ttf)),
                pw.SizedBox(height: 2),
                pw.Text('Delivery Receipt',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, font: ttf)),
                pw.Divider(thickness: 1, height: 8),
                pw.Text(cleanText,
                    style: pw.TextStyle(fontSize: 10, font: ttf),
                    textAlign: pw.TextAlign.center),
                pw.Divider(thickness: 1, height: 8),
                pw.Text('Thank you for your business!',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: ttf)),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Receipt.pdf',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt sent to printer!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      print('Print error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error printing: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ---------- Final Printable Receipt ----------
  Future<void> _showFinalReceipt({required double amount, required String method}) async {
    print('📢 _showFinalReceipt called with amount: $amount, method: $method');
    try {
      final shop = await supabase
          .from('shopkeepers')
          .select('shop_name, phone, address')
          .eq('id', _selectedShopkeeperId!)
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
      final previousBalance = _shopkeeperBalance - netAmount + amount;
      final amountPaid = amount;
      final newBalance = _shopkeeperBalance;

      final now = DateTime.now().toLocal();
      final receipt = '''
🧾 *FINAL RECEIPT*
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
*RETURNS*
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
*NET AMOUNT: ₹${netAmount.toStringAsFixed(2)}*
*PREVIOUS BALANCE: ₹${previousBalance.toStringAsFixed(2)}*
*AMOUNT PAID: ₹${amountPaid.toStringAsFixed(2)}*
*NEW BALANCE: ₹${newBalance.toStringAsFixed(2)}*
─────────────────────────
Payment Method: $method
Thank you for your business!
''';

      print('📄 Final receipt generated, showing dialog...');
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Final Receipt'),
          content: SingleChildScrollView(
            child: Text(
              receipt,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: receipt));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Receipt copied to clipboard!'), backgroundColor: Colors.green),
                );
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => _printReceiptDesktop(receipt),
              child: const Text('Print', style: TextStyle(color: Colors.blue)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      print('✅ Final receipt dialog closed.');
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('❌ Error in _showFinalReceipt: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error showing receipt: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ---------- Initial Receipt Dialog ----------
  Future<void> _showReceiptDialog() async {
    final shop = await supabase
        .from('shopkeepers')
        .select('shop_name, phone, address')
        .eq('id', _selectedShopkeeperId!)
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
    final previousBalance = _shopkeeperBalance - netAmount;
    final totalPayable = _shopkeeperBalance;

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
*NET AMOUNT: ₹${netAmount.toStringAsFixed(2)}*
*PREVIOUS BALANCE: ₹${previousBalance.toStringAsFixed(2)}*
*TOTAL OUTSTANDING: ₹${totalPayable.toStringAsFixed(2)}*
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
            onPressed: () {
              Clipboard.setData(ClipboardData(text: receipt));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Receipt copied to clipboard!'), backgroundColor: Colors.green),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () {
              if (mounted) {
                Navigator.pop(context);
                Future.delayed(const Duration(milliseconds: 300), () {
                  _collectPayment(defaultAmount: totalPayable);
                });
              }
            },
            child: const Text('Collect Payment', style: TextStyle(color: Colors.green)),
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

    if (mounted) {
      setState(() => _isSaving = true);
    }

    try {
      // Deduct master stock (orders)
      if (_orderItems.isNotEmpty) {
        await _deductMasterStock(_orderItems);
      }

      // Deduct driver stock (orders)
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

      // Add returns to driver stock
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

      // Add returns to master stock
      if (_returnItems.isNotEmpty) {
        await _addReturnsToMasterStock(_returnItems);
      }

      // Update or insert delivery record
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

      // Update shopkeeper balance
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
      final currentBalance = _shopkeeperBalance;
      final newBalance = currentBalance + netAmount;
      await supabase
          .from('shopkeepers')
          .update({'balance': newBalance})
          .eq('id', _selectedShopkeeperId!);
      if (mounted) {
        setState(() {
          _shopkeeperBalance = newBalance;
        });
      }

      await _showReceiptDialog();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  // ---------- Master Stock Helpers ----------
  Future<void> _deductMasterStock(List<Map<String, dynamic>> orderItems) async {
    final today = DateTime.now().toLocal().toString().split(' ')[0];
    for (var item in orderItems) {
      final productId = item['product_id'];
      final productName = item['name'];
      final qty = item['quantity'] as int;
      final masterRecord = await supabase
          .from('master_stock')
          .select('id, remaining_quantity')
          .eq('product_id', productId)
          .eq('date', today)
          .maybeSingle();
      if (masterRecord == null) {
        throw Exception('Master stock not found for product $productName.');
      }
      final current = masterRecord['remaining_quantity'] as int;
      final newStock = current - qty;
      if (newStock < 0) throw Exception('Insufficient master stock for $productName');
      await supabase
          .from('master_stock')
          .update({'remaining_quantity': newStock})
          .eq('id', masterRecord['id']);
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
        final current = masterRecord['remaining_quantity'] as int;
        final newStock = current + qty;
        await supabase
            .from('master_stock')
            .update({'remaining_quantity': newStock})
            .eq('id', masterRecord['id']);
      }
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
            // GPS
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

            // Shopkeeper
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
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Enter Order Quantities',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: (_isProcessingVoice || _isListening) ? null : _voiceOrder,
                      icon: _isProcessingVoice
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(_isListening ? Icons.mic : Icons.mic_none),
                      label: Text(_isProcessingVoice ? 'Processing...' : _isListening ? 'Listening...' : 'Voice Order'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isProcessingVoice
                            ? Colors.grey
                            : (_isListening ? Colors.red : Colors.purple),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_isListening)
                  const Text(
                    'Listening... Speak the full order (e.g., "5 Plain Chaach, 3 Paneer")',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                const SizedBox(height: 8),
                if (_isLoadingProducts)
                  const Center(child: CircularProgressIndicator())
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _products.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final p = _products[index];
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
                    },
                  ),
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
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _products.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final p = _products[index];
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
                    },
                  ),
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