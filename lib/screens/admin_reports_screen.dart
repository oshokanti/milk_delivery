import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = false;
  DateTimeRange _selectedDateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );

  List<Map<String, dynamic>> _deliveries = [];
  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _shopkeepers = [];
  Map<String, dynamic> _metrics = {};

  String? _selectedDriverId;
  String? _selectedShopkeeperId;

  // ----- Shopkeeper Monthly Analysis -----
  DateTime _selectedMonth = DateTime.now();
  Map<String, Map<String, dynamic>> _monthlyData = {}; // product_id -> {name, sold, revenue, returns}

  // ----- Product Monthly Performance -----
  List<Map<String, dynamic>> _products = [];
  String? _selectedProductId;
  DateTime _selectedProductMonth = DateTime.now();
  Map<int, int> _dailyProductSales = {}; // day -> quantity
  double _totalProductRevenue = 0;

  // ----- Helpers to parse items/returns -----
  List<dynamic> _parseItems(Map<String, dynamic> delivery) {
    final items = delivery['items'];
    if (items == null) return [];
    if (items is List) return items;
    if (items is String) {
      try {
        return jsonDecode(items) as List;
      } catch (_) {
        return [];
      }
    }
    return [];
  }

  List<dynamic> _parseReturns(Map<String, dynamic> delivery) {
    final returns = delivery['returns'];
    if (returns == null) return [];
    if (returns is List) return returns;
    if (returns is String) {
      try {
        return jsonDecode(returns) as List;
      } catch (_) {
        return [];
      }
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _fetchReports();
  }

  Future<void> _fetchProducts() async {
    try {
      final data = await supabase.from('products').select('id, name').order('name');
      setState(() {
        _products = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      print('Error fetching products: $e');
    }
  }

  Future<void> _fetchReports() async {
    setState(() => _isLoading = true);
    try {
      final start = _selectedDateRange.start.toLocal().toString().split(' ')[0];
      final end = _selectedDateRange.end.toLocal().toString().split(' ')[0];

      var query = supabase
          .from('deliveries')
          .select('*')
          .gte('delivered_at', start)
          .lte('delivered_at', end);

      if (_selectedDriverId != null && _selectedDriverId!.isNotEmpty) {
        query = query.eq('driver_id', _selectedDriverId!);
      }
      if (_selectedShopkeeperId != null && _selectedShopkeeperId!.isNotEmpty) {
        query = query.eq('shopkeeper_id', _selectedShopkeeperId!);
      }

      final response = await query;
      if (response is List) {
        _deliveries = List<Map<String, dynamic>>.from(response);
      } else {
        throw Exception('Unexpected response: $response');
      }

      // Enrich with driver and shopkeeper names
      for (var d in _deliveries) {
        final driverId = d['driver_id'];
        if (driverId != null) {
          final driver = await supabase
              .from('profiles')
              .select('name')
              .eq('id', driverId)
              .maybeSingle();
          d['profiles'] = driver;
        }
        final shopkeeperId = d['shopkeeper_id'];
        if (shopkeeperId != null) {
          final shop = await supabase
              .from('shopkeepers')
              .select('shop_name')
              .eq('id', shopkeeperId)
              .maybeSingle();
          d['shopkeepers'] = shop;
        }
      }

      final driversData = await supabase
          .from('profiles')
          .select('id, name')
          .eq('role', 'driver');
      _drivers = List<Map<String, dynamic>>.from(driversData);

      final shopkeepersData = await supabase
          .from('shopkeepers')
          .select('id, shop_name, balance');
      _shopkeepers = List<Map<String, dynamic>>.from(shopkeepersData);

      await _computeMonthlyAnalysis();
      await _fetchProductMonthlyData();

      _computeMetrics();
      setState(() => _isLoading = false);
    } catch (e) {
      print('Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
      setState(() => _isLoading = false);
    }
  }

  // ---------- Shopkeeper Monthly Analysis ----------
  Future<void> _computeMonthlyAnalysis() async {
    if (_selectedShopkeeperId == null || _selectedShopkeeperId!.isEmpty) {
      _monthlyData = {};
      return;
    }

    final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final monthEnd = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1).subtract(const Duration(days: 1));
    final start = monthStart.toLocal().toString().split(' ')[0];
    final end = monthEnd.toLocal().toString().split(' ')[0];

    final response = await supabase
        .from('deliveries')
        .select('*')
        .eq('shopkeeper_id', _selectedShopkeeperId!)
        .gte('delivered_at', start)
        .lte('delivered_at', end);

    final deliveries = response is List ? List<Map<String, dynamic>>.from(response) : [];

    Map<String, Map<String, dynamic>> agg = {};
    for (var d in deliveries) {
      final items = _parseItems(d);
      for (var item in items) {
        final productId = item['product_id'];
        final name = item['name'] ?? 'Unknown';
        final price = (item['price'] as num).toDouble();
        final qty = item['quantity'] as int;
        if (!agg.containsKey(productId)) {
          agg[productId] = {
            'name': name,
            'sold': 0,
            'revenue': 0.0,
            'returns': 0,
          };
        }
        agg[productId]!['sold'] = (agg[productId]!['sold'] as int) + qty;
        agg[productId]!['revenue'] = (agg[productId]!['revenue'] as double) + (price * qty);
      }
      final returns = _parseReturns(d);
      for (var r in returns) {
        final productId = r['product_id'];
        final qty = r['quantity'] as int;
        if (agg.containsKey(productId)) {
          agg[productId]!['returns'] = (agg[productId]!['returns'] as int) + qty;
        }
      }
    }
    setState(() {
      _monthlyData = agg;
    });
  }

  // ---------- Product Monthly Performance ----------
  Future<void> _fetchProductMonthlyData() async {
    if (_selectedProductId == null || _selectedProductId!.isEmpty) {
      _dailyProductSales = {};
      _totalProductRevenue = 0;
      return;
    }

    final monthStart = DateTime(_selectedProductMonth.year, _selectedProductMonth.month, 1);
    final monthEnd = DateTime(_selectedProductMonth.year, _selectedProductMonth.month + 1, 1).subtract(const Duration(days: 1));
    final start = monthStart.toLocal().toString().split(' ')[0];
    final end = monthEnd.toLocal().toString().split(' ')[0];

    final response = await supabase
        .from('deliveries')
        .select('*')
        .gte('delivered_at', start)
        .lte('delivered_at', end);

    final deliveries = response is List ? List<Map<String, dynamic>>.from(response) : [];

    Map<int, int> dailySales = {};
    double totalRevenue = 0;

    for (var d in deliveries) {
      final items = _parseItems(d);
      for (var item in items) {
        if (item['product_id'] == _selectedProductId) {
          final qty = item['quantity'] as int;
          final price = (item['price'] as num).toDouble();
          final day = DateTime.parse(d['delivered_at']).day;
          dailySales[day] = (dailySales[day] ?? 0) + qty;
          totalRevenue += price * qty;
        }
      }
    }

    setState(() {
      _dailyProductSales = dailySales;
      _totalProductRevenue = totalRevenue;
    });
  }

  // ---------- Metrics ----------
  void _computeMetrics() {
    double totalRevenue = 0;
    int totalReturns = 0;
    int totalOrders = _deliveries.length;
    Map<String, int> productSales = {};

    for (var d in _deliveries) {
      final items = _parseItems(d);
      for (var item in items) {
        final price = (item['price'] as num).toDouble();
        final qty = item['quantity'] as int;
        totalRevenue += price * qty;
        final name = item['name'] ?? 'Unknown';
        productSales[name] = (productSales[name] ?? 0) + qty;
      }
      final returns = _parseReturns(d);
      for (var r in returns) {
        totalReturns += r['quantity'] as int;
      }
    }

    String topProduct = 'N/A';
    int topQty = 0;
    productSales.forEach((name, qty) {
      if (qty > topQty) {
        topQty = qty;
        topProduct = name;
      }
    });

    _metrics = {
      'totalDeliveries': totalOrders,
      'totalRevenue': totalRevenue,
      'totalReturns': totalReturns,
      'topProduct': topProduct,
    };
  }

  // ---------- Export (CSV & PDF) ----------
  Future<void> _exportCSV() async {
    if (_deliveries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to export')),
      );
      return;
    }
    StringBuffer csvBuffer = StringBuffer();
    csvBuffer.writeln('Date,Shop,Driver,Items,Total,Status');
    for (var d in _deliveries) {
      final shop = d['shopkeepers']?['shop_name'] ?? 'Unknown';
      final driver = d['profiles']?['name'] ?? 'Unknown';
      final items = _parseItems(d).length;
      final total = (d['total_amount'] ?? 0).toString();
      final status = d['status'] ?? 'pending';
      final date = d['delivered_at'] ?? '';
      csvBuffer.writeln('$date,$shop,$driver,$items,$total,$status');
    }
    final csvString = csvBuffer.toString();
    final tempFile = File('${Directory.systemTemp.path}/report.csv');
    await tempFile.writeAsString(csvString);
    await Share.shareXFiles([XFile(tempFile.path)], text: 'Report export');
  }

  Future<void> _exportPDF() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          children: [
            pw.Text('Delivery Report', style: pw.TextStyle(fontSize: 24)),
            pw.SizedBox(height: 20),
            pw.Text('From ${_selectedDateRange.start.toLocal().toString().split(' ')[0]} to ${_selectedDateRange.end.toLocal().toString().split(' ')[0]}'),
            pw.SizedBox(height: 20),
            pw.Table(
              border: pw.TableBorder.all(),
              children: [
                pw.TableRow(
                  children: ['Date', 'Shop', 'Driver', 'Total'].map((e) => pw.Text(e)).toList(),
                ),
                ..._deliveries.map((d) {
                  return pw.TableRow(
                    children: [
                      pw.Text(d['delivered_at']?.split(' ')[0] ?? ''),
                      pw.Text(d['shopkeepers']?['shop_name'] ?? ''),
                      pw.Text(d['profiles']?['name'] ?? ''),
                      pw.Text((d['total_amount'] ?? 0).toString()),
                    ],
                  );
                }).toList(),
              ],
            ),
          ],
        ),
      ),
    );
    await Printing.sharePdf(bytes: await pdf.save(), filename: 'report.pdf');
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Reports'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchReports,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- Date Range Picker ----
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.date_range, color: Colors.blue),
                          const SizedBox(width: 12),
                          Text(
                            '${DateFormat('dd/MM/yyyy').format(_selectedDateRange.start)} - ${DateFormat('dd/MM/yyyy').format(_selectedDateRange.end)}',
                            style: const TextStyle(fontSize: 16),
                          ),
                          const Spacer(),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              DateTime now = DateTime.now();
                              DateTime start;
                              switch (value) {
                                case 'today':
                                  start = now;
                                  break;
                                case 'week':
                                  start = now.subtract(const Duration(days: 7));
                                  break;
                                case 'month':
                                  start = DateTime(now.year, now.month, 1);
                                  break;
                                case 'custom':
                                  _showDateRangePicker();
                                  return;
                                default:
                                  return;
                              }
                              setState(() {
                                _selectedDateRange = DateTimeRange(start: start, end: now);
                              });
                              _fetchReports();
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: 'today', child: Text('Today')),
                              const PopupMenuItem(value: 'week', child: Text('This Week')),
                              const PopupMenuItem(value: 'month', child: Text('This Month')),
                              const PopupMenuItem(value: 'custom', child: Text('Custom Range')),
                            ],
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ---- Filters ----
                  Row(
                    children: [
                      Expanded(
                        child: _buildFilterDropdown(
                          hint: 'Driver',
                          items: _drivers,
                          value: _selectedDriverId,
                          onChanged: (val) {
                            setState(() => _selectedDriverId = val);
                            _fetchReports();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildFilterDropdown(
                          hint: 'Shopkeeper',
                          items: _shopkeepers.map((s) => {'id': s['id'], 'name': s['shop_name']}).toList(),
                          value: _selectedShopkeeperId,
                          onChanged: (val) {
                            setState(() => _selectedShopkeeperId = val);
                            _fetchReports();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ---- Metrics Cards ----
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildMetricCard('Deliveries', '${_metrics['totalDeliveries']}', Colors.orange),
                      _buildMetricCard('Revenue', '₹${(_metrics['totalRevenue'] ?? 0).toStringAsFixed(0)}', Colors.green),
                      _buildMetricCard('Returns', '${_metrics['totalReturns']}', Colors.red),
                      _buildMetricCard('Top Product', _metrics['topProduct'] ?? 'N/A', Colors.purple),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ---- Charts ----
                  const Text('Daily Deliveries', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildBarChart(),
                  const SizedBox(height: 24),
                  const Text('Product Sales (Top 5)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildPieChart(),
                  const SizedBox(height: 24),

                  // ---- Driver Performance ----
                  const Text('Driver Performance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildDriverTable(),
                  const SizedBox(height: 24),

                  // ---- Shopkeeper Balances ----
                  const Text('Shopkeeper Balances', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildShopkeeperBalances(),
                  const SizedBox(height: 24),

                  // ---- Shopkeeper Monthly Analysis ----
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Shopkeeper Monthly Analysis',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildFilterDropdown(
                                  hint: 'Select Shopkeeper',
                                  items: _shopkeepers.map((s) => {'id': s['id'], 'name': s['shop_name']}).toList(),
                                  value: _selectedShopkeeperId,
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedShopkeeperId = val;
                                    });
                                    _fetchReports();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.calendar_month),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _selectedMonth,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                    initialDatePickerMode: DatePickerMode.year,
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _selectedMonth = picked;
                                    });
                                    await _computeMonthlyAnalysis();
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_selectedShopkeeperId == null || _selectedShopkeeperId!.isEmpty)
                            const Text('Please select a shopkeeper to view monthly analysis.')
                          else if (_monthlyData.isEmpty)
                            const Text('No data for this shopkeeper in the selected month.')
                          else
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columnSpacing: 16,
                                headingRowColor: MaterialStateProperty.all(Colors.blue.shade50),
                                columns: const [
                                  DataColumn(label: Text('Product')),
                                  DataColumn(label: Text('Sold')),
                                  DataColumn(label: Text('Revenue')),
                                  DataColumn(label: Text('Returns')),
                                ],
                                rows: _monthlyData.entries.map((entry) {
                                  final data = entry.value;
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(data['name'])),
                                      DataCell(Text(data['sold'].toString())),
                                      DataCell(Text('₹${data['revenue'].toStringAsFixed(2)}')),
                                      DataCell(Text(data['returns'].toString())),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          const SizedBox(height: 8),
                          if (_monthlyData.isNotEmpty) ...[
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total Revenue: ₹${_monthlyData.values.fold<double>(0, (sum, data) => sum + (data['revenue'] as double)).toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Total Returns: ${_monthlyData.values.fold<int>(0, (sum, data) => sum + (data['returns'] as int))}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ---- NEW: Product Monthly Performance ----
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Product Monthly Performance',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildFilterDropdown(
                                  hint: 'Select Product',
                                  items: _products,
                                  value: _selectedProductId,
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedProductId = val;
                                    });
                                    _fetchProductMonthlyData();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.calendar_month),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _selectedProductMonth,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                    initialDatePickerMode: DatePickerMode.year,
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _selectedProductMonth = picked;
                                    });
                                    await _fetchProductMonthlyData();
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_selectedProductId == null || _selectedProductId!.isEmpty)
                            const Text('Please select a product to view monthly performance.')
                          else if (_dailyProductSales.isEmpty)
                            const Text('No sales for this product in the selected month.')
                          else
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columnSpacing: 20,
                                headingRowColor: MaterialStateProperty.all(Colors.green.shade50),
                                columns: const [
                                  DataColumn(label: Text('Date')),
                                  DataColumn(label: Text('Quantity Sold')),
                                ],
                                rows: List.generate(
                                  1 + _dailyProductSales.length,
                                  (index) {
                                    if (index == 0) {
                                      // total row
                                      final total = _dailyProductSales.values.fold<int>(0, (sum, qty) => sum + qty);
                                      return DataRow(
                                        cells: [
                                          DataCell(const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataCell(Text('$total', style: const TextStyle(fontWeight: FontWeight.bold))),
                                        ],
                                      );
                                    }
                                    final day = _dailyProductSales.keys.toList()[index - 1];
                                    final qty = _dailyProductSales[day]!;
                                    return DataRow(
                                      cells: [
                                        DataCell(Text('$day/${_selectedProductMonth.month}/${_selectedProductMonth.year}')),
                                        DataCell(Text(qty.toString())),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          if (_dailyProductSales.isNotEmpty) ...[
                            const Divider(),
                            Text(
                              'Total Revenue: ₹${_totalProductRevenue.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ---- Export Buttons ----
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _exportCSV,
                          icon: const Icon(Icons.file_download),
                          label: const Text('CSV'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _exportPDF,
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('PDF'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  // ---- Helper Widgets ----
  Widget _buildFilterDropdown({required String hint, required List items, required String? value, required Function(String?) onChanged}) {
    return DropdownButtonFormField<String>(
      value: value,
      hint: Text(hint),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('All')),
        ...items.map((item) {
          return DropdownMenuItem<String>(
            value: item['id'],
            child: Text(item['name'] ?? 'Unknown'),
          );
        }).toList(),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildBarChart() {
    Map<String, int> dailyCount = {};
    for (var d in _deliveries) {
      final date = d['delivered_at']?.split(' ')[0] ?? '';
      if (date.isNotEmpty) {
        dailyCount[date] = (dailyCount[date] ?? 0) + 1;
      }
    }
    final sortedDates = dailyCount.keys.toList()..sort();
    final bars = sortedDates.map((date) {
      final count = dailyCount[date] ?? 0;
      return BarChartGroupData(
        x: sortedDates.indexOf(date),
        barRods: [
          BarChartRodData(toY: count.toDouble(), color: Colors.blue),
        ],
      );
    }).toList();

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          barGroups: bars,
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx >= 0 && idx < sortedDates.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(sortedDates[idx].split('-').last, style: const TextStyle(fontSize: 10)),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPieChart() {
    Map<String, int> productSales = {};
    for (var d in _deliveries) {
      final items = _parseItems(d);
      for (var item in items) {
        final name = item['name'] ?? 'Unknown';
        productSales[name] = (productSales[name] ?? 0) + (item['quantity'] as int);
      }
    }
    final sorted = productSales.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top5 = sorted.take(5).toList();
    final others = sorted.skip(5).fold(0, (sum, e) => sum + e.value);
    final List<PieChartSectionData> sections = [];
    for (int i = 0; i < top5.length; i++) {
      sections.add(
        PieChartSectionData(
          value: top5[i].value.toDouble(),
          title: top5[i].key,
          color: Colors.primaries[i % Colors.primaries.length],
        ),
      );
    }
    if (others > 0) {
      sections.add(
        PieChartSectionData(
          value: others.toDouble(),
          title: 'Others',
          color: Colors.grey,
        ),
      );
    }
    return SizedBox(
      height: 200,
      child: PieChart(PieChartData(sections: sections)),
    );
  }

  Widget _buildDriverTable() {
    Map<String, Map<String, dynamic>> driverStats = {};
    for (var d in _deliveries) {
      final driverId = d['driver_id'];
      final driverName = d['profiles']?['name'] ?? 'Unknown';
      if (!driverStats.containsKey(driverId)) {
        driverStats[driverId] = {'name': driverName, 'count': 0, 'revenue': 0.0};
      }
      driverStats[driverId]!['count'] = (driverStats[driverId]!['count'] as int) + 1;
      final items = _parseItems(d);
      for (var item in items) {
        driverStats[driverId]!['revenue'] = (driverStats[driverId]!['revenue'] as double) + (item['price'] as num).toDouble() * (item['quantity'] as int);
      }
    }
    final list = driverStats.values.toList();
    list.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final item = list[index];
        return ListTile(
          leading: const Icon(Icons.person),
          title: Text(item['name']),
          subtitle: Text('Deliveries: ${item['count']}'),
          trailing: Text('₹${(item['revenue'] ?? 0).toStringAsFixed(0)}'),
        );
      },
    );
  }

  Widget _buildShopkeeperBalances() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _shopkeepers.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final shop = _shopkeepers[index];
        final balance = (shop['balance'] ?? 0).toDouble();
        return ExpansionTile(
          leading: const Icon(Icons.store),
          title: Text(shop['shop_name'] ?? 'Unknown'),
          subtitle: Text('Balance: ₹${balance.toStringAsFixed(2)}'),
          trailing: Text(
            balance > 0 ? '₹${balance.toStringAsFixed(2)}' : '₹0.00',
            style: TextStyle(
              color: balance > 0 ? Colors.red : Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Payment History (last 5)'),
                  const SizedBox(height: 8),
                  const Text('No transactions yet', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDateRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
    );
    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
      _fetchReports();
    }
  }
}