import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:realtime_client/realtime_client.dart' show PostgresChangeEvent, PostgresChangePayload;
import 'package:milk_delivery/screens/shop_delivery_flow_screen.dart';
import 'package:milk_delivery/screens/load_stock_screen.dart';
import 'package:milk_delivery/screens/driver_payment_screen.dart';

class DriverDashboard extends StatefulWidget {
  final String driverId;
  const DriverDashboard({super.key, required this.driverId});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  final supabase = Supabase.instance.client;
  late Future<Map<String, dynamic>> _dataFuture;

  // Realtime channel for driver stock
  RealtimeChannel? _stockChannel;

  // GPS & Nearby Shops
  Position? _currentPosition;
  bool _isLoadingGps = false;
  String? _gpsError;
  List<Map<String, dynamic>> _nearbyShops = [];
  List<Map<String, dynamic>> _allShops = [];
  static const double _mockLat = 19.0760;
  static const double _mockLng = 72.8777;

  // QR Scanner
  bool _isScanning = false;

  // ---------- LIFECYCLE ----------
  @override
  void initState() {
    super.initState();
    _dataFuture = _loadDriverData();
    _getCurrentLocation();
    _fetchAllShops();
    _subscribeToDriverStockChanges();
  }

  @override
  void dispose() {
    _stockChannel?.unsubscribe();
    _stockChannel = null;
    super.dispose();
  }

  // ---------- REALTIME SUBSCRIPTION ----------
  void _subscribeToDriverStockChanges() {
    print('📡 Subscribing to driver_stock changes...');
    _stockChannel = supabase.channel('driver_stock_changes');
    _stockChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'driver_stock',
          callback: (payload) => _handleDriverStockChange(payload),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'driver_stock',
          callback: (payload) => _handleDriverStockChange(payload),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'driver_stock',
          callback: (payload) => _handleDriverStockChange(payload),
        )
        .subscribe((status, error) {
          if (error != null) {
            print('❌ Driver stock Realtime error: $error');
          } else {
            print('✅ Subscribed to driver_stock_changes');
          }
        });
  }

  void _handleDriverStockChange(PostgresChangePayload payload) {
    final newData = payload.newRecord;
    final today = DateTime.now().toLocal().toString().split(' ')[0];
    if (newData != null &&
        newData['driver_id'] == widget.driverId &&
        newData['date'] == today) {
      print('🔄 Driver stock changed – refreshing...');
      setState(() {
        _dataFuture = _loadDriverData();
      });
    }
  }

  // ---------- GPS & DISTANCE ----------
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

  // ---------- SHOPS ----------
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
      _nearbyShops = filtered.take(3).toList();
    });
  }

  // ---------- QR SCANNER ----------
  Future<void> _scanShopQR() async {
    setState(() => _isScanning = true);
    try {
      final barcode = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text('Scan Shop QR'),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            body: MobileScanner(
              onDetect: (capture) {
                final String? raw = capture.barcodes.first.rawValue;
                if (raw != null) {
                  Navigator.pop(context, raw);
                }
              },
              controller: MobileScannerController(
                detectionSpeed: DetectionSpeed.normal,
                facing: CameraFacing.back,
              ),
              placeholderBuilder: (context, child) => const Center(
                child: Text('Point camera at shop QR code'),
              ),
            ),
          ),
        ),
      );
      setState(() => _isScanning = false);
      if (barcode != null) {
        final shopData = await supabase
            .from('shopkeepers')
            .select('*')
            .eq('barcode_id', barcode)
            .maybeSingle();
        if (shopData == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid QR code. No shop found.'), backgroundColor: Colors.red),
          );
          return;
        }
        _startDeliveryForShop(shopData);
      }
    } catch (e) {
      setState(() => _isScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error scanning: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _startDeliveryForShop(Map<String, dynamic> shop) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShopDeliveryFlowScreen(
          delivery: {
            'id': 'new',
            'shop_name': shop['shop_name'],
            'address': shop['address'],
            'status': 'pending',
          },
          driverId: widget.driverId,
          preSelectedShopId: shop['id'],
        ),
      ),
    );
  }

  // ---------- LOAD DATA ----------
  Future<Map<String, dynamic>> _loadDriverData() async {
    try {
      final driverId = widget.driverId;
      final profileResponse = await supabase
          .from('profiles')
          .select('name')
          .eq('id', driverId)
          .maybeSingle();
      final driverName = profileResponse?['name'] ?? 'Driver';

      final response = await supabase
          .from('deliveries')
          .select('*')
          .eq('driver_id', driverId)
          .order('created_at');
      final List<Map<String, dynamic>> deliveries =
          (response as List?)?.cast<Map<String, dynamic>>() ?? [];

      final pendingCount = deliveries.where((d) => d['status'] != 'delivered').length;
      final deliveredCount = deliveries.where((d) => d['status'] == 'delivered').length;

      final today = DateTime.now().toLocal().toString().split(' ')[0];
      List<Map<String, dynamic>> stockItems = [];
      try {
        final stockData = await supabase
            .from('driver_stock')
            .select('*, products(name, unit)')
            .eq('driver_id', driverId)
            .eq('date', today);
        stockItems = List<Map<String, dynamic>>.from(stockData);
      } catch (e) {
        print('⚠️ Could not fetch stock items: $e');
      }

      Map<String, dynamic>? activeSession;
      try {
        final sessionData = await supabase
            .from('driver_sessions')
            .select('*')
            .eq('driver_id', driverId)
            .eq('status', 'active')
            .maybeSingle();
        if (sessionData != null) activeSession = sessionData;
      } catch (e) {
        print('⚠️ Could not fetch active session: $e');
      }

      return {
        'driverName': driverName,
        'deliveries': deliveries,
        'pendingCount': pendingCount,
        'deliveredCount': deliveredCount,
        'stockItems': stockItems,
        'activeSession': activeSession,
        'error': null,
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'driverName': 'Driver',
        'deliveries': <Map<String, dynamic>>[],
        'pendingCount': 0,
        'deliveredCount': 0,
        'stockItems': <Map<String, dynamic>>[],
        'activeSession': null,
      };
    }
  }

  String _formatTime(String timestamp) {
    final dt = DateTime.parse(timestamp).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _startDay() async {
    try {
      await supabase.from('driver_sessions').insert({
        'driver_id': widget.driverId,
        'status': 'active',
        'start_time': DateTime.now().toUtc().toIso8601String(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Day started!'), backgroundColor: Colors.green),
      );
      setState(() {
        _dataFuture = _loadDriverData();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error starting day: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _endDay() async {
    final data = await _dataFuture;
    final session = data?['activeSession'] as Map?;
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active session to end'), backgroundColor: Colors.orange),
      );
      return;
    }
    try {
      await supabase
          .from('driver_sessions')
          .update({
            'status': 'closed',
            'end_time': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', session['id']);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Day ended!'), backgroundColor: Colors.green),
      );
      setState(() {
        _dataFuture = _loadDriverData();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error ending day: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ---------- BUILD ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacementNamed(context, '/'),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _dataFuture = _loadDriverData();
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data!;
          final driverName = data['driverName'] as String? ?? 'Driver';
          final deliveries = (data['deliveries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          final pendingCount = data['pendingCount'] as int? ?? 0;
          final deliveredCount = data['deliveredCount'] as int? ?? 0;
          final stockItems = (data['stockItems'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          final activeSession = data['activeSession'] as Map?;
          final bool isActive = activeSession != null;

          return RefreshIndicator(
            onRefresh: () async {
              await _getCurrentLocation();
              await _fetchAllShops();
              setState(() {
                _dataFuture = _loadDriverData();
              });
              await _dataFuture;
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome
                  Text('Welcome, $driverName', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Today: ${DateTime.now().toLocal().toString().split(' ')[0]}',
                      style: const TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 16),

                  // Stock in Vehicle
                  const Text('Stock in Vehicle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  stockItems.isEmpty
                      ? const Text('No stock loaded today', style: TextStyle(color: Colors.grey))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: stockItems.map((item) {
                            final product = item['products'] as Map? ?? {};
                            final name = product['name'] ?? 'Unknown';
                            final quantity = item['quantity_loaded'] as int? ?? 0;
                            final unit = product['unit'] ?? '';
                            final colors = [Colors.blue.shade100, Colors.teal.shade100, Colors.green.shade100, Colors.orange.shade100, Colors.purple.shade100, Colors.pink.shade100, Colors.indigo.shade100, Colors.lime.shade100];
                            final Color bgColor = colors[stockItems.indexOf(item) % colors.length];
                            final Color accentColor = bgColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
                            return Expanded(
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), spreadRadius: 2, blurRadius: 6)],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('$quantity', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: accentColor)),
                                    const SizedBox(height: 4),
                                    Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accentColor.withOpacity(0.8)), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                                    if (unit.isNotEmpty) Text(unit, style: TextStyle(fontSize: 10, color: accentColor.withOpacity(0.6))),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                  const SizedBox(height: 16),

                  // Session status
                  if (isActive) ...[
                    Row(
                      children: [
                        const Icon(Icons.circle, color: Colors.green, size: 12),
                        const SizedBox(width: 8),
                        Text('🟢 Active since ${_formatTime(activeSession!['start_time'])}',
                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],

                  // ---- Nearby Shops ----
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Nearby Shops', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            onPressed: () {
                              _getCurrentLocation();
                              _fetchAllShops();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner, size: 20),
                            onPressed: _scanShopQR,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _isLoadingGps
                      ? const SizedBox(height: 30, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                      : _gpsError != null
                          ? Text('GPS error: $_gpsError', style: const TextStyle(color: Colors.red, fontSize: 14))
                          : _nearbyShops.isEmpty
                              ? Column(
                                  children: [
                                    const Text('No nearby shops found within 5 km.',
                                        style: TextStyle(color: Colors.grey)),
                                    const SizedBox(height: 8),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ShopDeliveryFlowScreen(
                                              delivery: {'id': 'new', 'shop_name': '', 'address': '', 'status': 'pending'},
                                              driverId: widget.driverId,
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.add),
                                      label: const Text('Create New Shopkeeper'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.teal,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  children: _nearbyShops.map((shop) {
                                    final distance = _currentPosition != null && shop['latitude'] != null && shop['longitude'] != null
                                        ? _calculateDistance(
                                            _currentPosition!.latitude,
                                            _currentPosition!.longitude,
                                            shop['latitude'] as double,
                                            shop['longitude'] as double,
                                          ).toStringAsFixed(1)
                                        : '?';
                                    return Card(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      child: ListTile(
                                        leading: const Icon(Icons.store, color: Colors.teal),
                                        title: Text(shop['shop_name'] ?? 'Unknown'),
                                        subtitle: Text('${shop['address']} • ${distance} km'),
                                        trailing: ElevatedButton(
                                          onPressed: () => _startDeliveryForShop(shop),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          ),
                                          child: const Text('Start'),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                  const SizedBox(height: 16),

                  // Stats cards
                  Row(
                    children: [
                      _buildStatCard('Pending', '$pendingCount', Colors.orange),
                      const SizedBox(width: 8),
                      _buildStatCard('Delivered', '$deliveredCount', Colors.green),
                      const SizedBox(width: 8),
                      _buildStatCard('Total Stock', '${stockItems.fold<int>(0, (sum, item) => sum + (item['quantity_loaded'] as int? ?? 0))}', Colors.blue),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Actions row
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LoadStockScreen(driverId: widget.driverId),
                              ),
                            );
                            if (result == true) {
                              setState(() {
                                _dataFuture = _loadDriverData();
                              });
                            }
                          },
                          icon: const Icon(Icons.inventory),
                          label: const Text('Load Stock'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isActive ? _endDay : _startDay,
                          icon: Icon(isActive ? Icons.stop : Icons.play_arrow),
                          label: Text(isActive ? 'End Day' : 'Start Day'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isActive ? Colors.red : Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Today's Deliveries
                  const Text('Today\'s Deliveries', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  deliveries.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No deliveries today')))
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: deliveries.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) {
                            final delivery = deliveries[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getStatusColor(delivery['status']),
                                child: Icon(_getStatusIcon(delivery['status']), color: Colors.white),
                              ),
                              title: Text(delivery['shop_name'] ?? 'Unknown'),
                              subtitle: Text('${delivery['address'] ?? ''}\nItems: ${delivery['items'] ?? ''}'),
                              trailing: Text(
                                (delivery['status'] ?? 'pending').toUpperCase(),
                                style: TextStyle(color: _getStatusColor(delivery['status']), fontWeight: FontWeight.bold),
                              ),
                              onTap: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ShopDeliveryFlowScreen(
                                      delivery: delivery,
                                      driverId: widget.driverId,
                                    ),
                                  ),
                                );
                                if (result == true) {
                                  setState(() {
                                    _dataFuture = _loadDriverData();
                                  });
                                }
                              },
                            );
                          },
                        ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---- Helper Widgets ----
  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
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

  IconData _getStatusIcon(String? status) {
    switch (status) {
      case 'delivered':
        return Icons.check_circle;
      case 'in_transit':
        return Icons.delivery_dining;
      case 'pending':
        return Icons.pending;
      default:
        return Icons.help;
    }
  }
}