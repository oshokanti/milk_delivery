import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VehicleManagementScreen extends StatefulWidget {
  const VehicleManagementScreen({super.key});

  @override
  State<VehicleManagementScreen> createState() => _VehicleManagementScreenState();
}

class _VehicleManagementScreenState extends State<VehicleManagementScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> vehicles = [];
  bool isLoading = true;

  final _numberController = TextEditingController();
  final _typeController = TextEditingController();
  final _capacityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchVehicles();
  }

  Future<void> fetchVehicles() async {
    setState(() => isLoading = true);
    try {
      final data = await supabase.from('vehicles').select('*').order('created_at');
      setState(() {
        vehicles = List<Map<String, dynamic>>.from(data);
        isLoading = false;
      });
    } catch (e) {
      print('Error fetching vehicles: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _addVehicle() async {
    if (_numberController.text.isEmpty ||
        _typeController.text.isEmpty ||
        _capacityController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All fields are required')),
      );
      return;
    }

    try {
      await supabase.from('vehicles').insert({
        'vehicle_number': _numberController.text.trim(),
        'vehicle_type': _typeController.text.trim(),
        'capacity': int.parse(_capacityController.text.trim()),
      });

      _numberController.clear();
      _typeController.clear();
      _capacityController.clear();
      Navigator.pop(context);
      await fetchVehicles();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle added successfully'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleVehicleStatus(Map<String, dynamic> vehicle) async {
    final newStatus = !vehicle['is_active'];
    try {
      await supabase
          .from('vehicles')
          .update({'is_active': newStatus})
          .eq('id', vehicle['id']);
      await fetchVehicles();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteVehicle(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Vehicle?'),
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
        await supabase.from('vehicles').delete().eq('id', id);
        await fetchVehicles();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Vehicle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _numberController,
              decoration: const InputDecoration(labelText: 'Vehicle Number'),
            ),
            TextField(
              controller: _typeController,
              decoration: const InputDecoration(labelText: 'Vehicle Type (e.g., Bike, Van, Truck)'),
            ),
            TextField(
              controller: _capacityController,
              decoration: const InputDecoration(labelText: 'Capacity (in units)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _addVehicle,
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicles'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddDialog,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : vehicles.isEmpty
              ? const Center(child: Text('No vehicles added yet'))
              : ListView.builder(
                  itemCount: vehicles.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) {
                    final vehicle = vehicles[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: vehicle['is_active'] ? Colors.green : Colors.red,
                          child: Text(
                            vehicle['vehicle_number'][0],
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(vehicle['vehicle_number']),
                        subtitle: Text(
                          '${vehicle['vehicle_type']} - Capacity: ${vehicle['capacity']} units',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                vehicle['is_active'] ? Icons.check_circle : Icons.cancel,
                                color: vehicle['is_active'] ? Colors.green : Colors.red,
                              ),
                              onPressed: () => _toggleVehicleStatus(vehicle),
                              tooltip: vehicle['is_active'] ? 'Deactivate' : 'Activate',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteVehicle(vehicle['id']),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}