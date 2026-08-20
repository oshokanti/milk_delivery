import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:barcode/barcode.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class DriverManagementScreen extends StatefulWidget {
  const DriverManagementScreen({super.key});

  @override
  State<DriverManagementScreen> createState() => _DriverManagementScreenState();
}

class _DriverManagementScreenState extends State<DriverManagementScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> drivers = [];
  List<Map<String, dynamic>> vehicles = [];
  bool isLoading = true;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _selectedVehicleId;
  String? _editingDriverId;
  String? _currentBarcodeId;

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> fetchData() async {
    setState(() => isLoading = true);
    try {
      final driversData = await supabase
          .from('profiles')
          .select('*, vehicles(vehicle_number, vehicle_type)')
          .eq('role', 'driver')
          .order('created_at');

      final vehiclesData = await supabase
          .from('vehicles')
          .select('*')
          .eq('is_active', true)
          .order('vehicle_number');

      setState(() {
        drivers = List<Map<String, dynamic>>.from(driversData);
        vehicles = List<Map<String, dynamic>>.from(vehiclesData);
        isLoading = false;
      });
    } catch (e) {
      _showError('Failed to load data: $e');
      setState(() => isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> _printQRCode(String barcodeId) async {
    try {
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            return pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    'Driver QR Code',
                    style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 20),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: barcodeId,
                    width: 200,
                    height: 200,
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    barcodeId,
                    style: pw.TextStyle(fontSize: 14),
                  ),
                ],
              ),
            );
          },
        ),
      );
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'driver_qr_$barcodeId.pdf',
      );
    } catch (e) {
      _showError('Print error: $e');
    }
  }

  Future<void> _resetPIN(String driverId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset PIN?'),
        content: const Text('This will clear the driver\'s PIN. They will be asked to create a new one on next login. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await supabase
            .from('profiles')
            .update({'pin_hash': null})
            .eq('id', driverId);
        _showSuccess('PIN reset successfully. Driver will be asked to create a new PIN on next login.');
        await fetchData();
        Navigator.pop(context); // close edit dialog
      } catch (e) {
        _showError('Error resetting PIN: $e');
      }
    }
  }

  Future<void> _saveDriver({bool regenerateQR = false}) async {
    if (_nameController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _selectedVehicleId == null) {
      _showError('All fields are required');
      return;
    }

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');

      String barcodeId;
      if (_editingDriverId != null && !regenerateQR) {
        barcodeId = _currentBarcodeId!;
      } else {
        barcodeId =
            'DRV-${_phoneController.text.trim()}-${DateTime.now().millisecondsSinceEpoch.toString().substring(8, 12)}';
      }

      final Map<String, dynamic> driverData = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'vehicle_id': _selectedVehicleId,
        'role': 'driver',
        'barcode_id': barcodeId,
        'is_active': true,
        'user_id': user.id,
        // pin_hash is not set – remains null for new drivers
      };

      if (_editingDriverId != null) {
        // When updating, we keep the existing pin_hash unless we explicitly reset it
        await supabase
            .from('profiles')
            .update(driverData)
            .eq('id', _editingDriverId!);
        _showSuccess('Driver updated');
      } else {
        await supabase.from('profiles').insert(driverData);
        _showSuccess('Driver created');
      }

      _nameController.clear();
      _phoneController.clear();
      setState(() {
        _selectedVehicleId = null;
        _editingDriverId = null;
        _currentBarcodeId = null;
      });
      await fetchData();
      Navigator.pop(context);
    } catch (e) {
      _showError('Error: $e');
    }
  }

  void _showAddDialog({Map<String, dynamic>? driver}) {
    if (driver != null) {
      _editingDriverId = driver['id'];
      _currentBarcodeId = driver['barcode_id'];
      _nameController.text = driver['name'] ?? '';
      _phoneController.text = driver['phone'] ?? '';
      _selectedVehicleId = driver['vehicle_id'];
    } else {
      _editingDriverId = null;
      _currentBarcodeId = null;
      _nameController.clear();
      _phoneController.clear();
      _selectedVehicleId = null;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(driver == null ? 'Add Driver' : 'Edit Driver'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Driver Name'),
              ),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedVehicleId,
                hint: const Text('Select Vehicle'),
                items: vehicles.map((v) {
                  return DropdownMenuItem<String>(
                    value: v['id'],
                    child: Text('${v['vehicle_number']} - ${v['vehicle_type']}'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedVehicleId = value;
                  });
                },
              ),
              if (driver != null && driver['barcode_id'] != null) ...[
                const SizedBox(height: 12),
                const Text('QR Code:', style: TextStyle(fontWeight: FontWeight.bold)),
                BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: driver['barcode_id'],
                  width: 120,
                  height: 120,
                ),
                Text(
                  driver['barcode_id'],
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _printQRCode(driver['barcode_id']),
                      icon: const Icon(Icons.print),
                      label: const Text('Print QR'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Regenerate QR?'),
                            content: const Text('This will create a new barcode for this driver. The old one will no longer work. Continue?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Regenerate', style: TextStyle(color: Colors.orange)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await _saveDriver(regenerateQR: true);
                        }
                      },
                      icon: const Icon(Icons.qr_code),
                      label: const Text('Regenerate QR'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // ---- NEW: Reset PIN Button ----
                if (driver['pin_hash'] != null)
                  ElevatedButton.icon(
                    onPressed: () => _resetPIN(driver['id']),
                    icon: const Icon(Icons.lock_reset),
                    label: const Text('Reset PIN'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _saveDriver(regenerateQR: false),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDriver(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Driver?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await supabase.from('profiles').delete().eq('id', id);
        await fetchData();
      } catch (e) {
        _showError('Error: $e');
      }
    }
  }

  Future<void> _toggleDriverStatus(Map<String, dynamic> driver) async {
    final newStatus = !driver['is_active'];
    try {
      await supabase
          .from('profiles')
          .update({'is_active': newStatus})
          .eq('id', driver['id']);
      await fetchData();
    } catch (e) {
      _showError('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drivers'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddDialog(),
            tooltip: 'Add Driver',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: fetchData,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : drivers.isEmpty
                ? const Center(child: Text('No drivers added yet'))
                : ListView.builder(
                    itemCount: drivers.length,
                    padding: const EdgeInsets.all(8),
                    itemBuilder: (context, index) {
                      final driver = drivers[index];
                      final vehicle = driver['vehicles'] as Map? ?? {};
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: driver['is_active'] ? Colors.green : Colors.red,
                            child: Text(
                              driver['name']?[0] ?? 'D',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(driver['name'] ?? 'Unknown'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Phone: ${driver['phone']}'),
                              Text('Vehicle: ${vehicle['vehicle_number'] ?? 'Not assigned'}'),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _showAddDialog(driver: driver),
                              ),
                              IconButton(
                                icon: Icon(
                                  driver['is_active'] ? Icons.check_circle : Icons.cancel,
                                  color: driver['is_active'] ? Colors.green : Colors.red,
                                ),
                                onPressed: () => _toggleDriverStatus(driver),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteDriver(driver['id']),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}