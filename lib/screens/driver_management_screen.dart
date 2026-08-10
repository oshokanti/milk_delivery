import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:barcode/barcode.dart';

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

  Future<void> _saveDriver() async {
    if (_nameController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _selectedVehicleId == null) {
      _showError('All fields are required');
      return;
    }

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final barcodeId =
          'DRV-${_phoneController.text.trim()}-${DateTime.now().millisecondsSinceEpoch.toString().substring(8, 12)}';

      final Map<String, dynamic> driverData = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'vehicle_id': _selectedVehicleId,
        'role': 'driver',
        'barcode_id': barcodeId,
        'is_active': true,
        'user_id': user.id, // placeholder
      };

      if (_editingDriverId != null) {
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
      _nameController.text = driver['name'] ?? '';
      _phoneController.text = driver['phone'] ?? '';
      _selectedVehicleId = driver['vehicle_id'];
    } else {
      _editingDriverId = null;
      _nameController.clear();
      _phoneController.clear();
      _selectedVehicleId = null;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
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
                if (driver != null && driver['barcode_id'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Column(
                      children: [
                        const Text('QR Code:'),
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
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _saveDriver,
              child: const Text('Save'),
            ),
          ],
        );
      },
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