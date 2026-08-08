import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:milk_delivery/screens/login_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, dynamic>> deliveries = [];
  bool isLoading = true;
  int pendingCount = 0;
  int completedCount = 0;

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    fetchDeliveries();
  }

  Future<void> fetchDeliveries() async {
    setState(() {
      isLoading = true;
    });

    try {
      // Get current user
      final user = supabase.auth.currentUser;
      
      // Fetch deliveries for this driver (using a sample driver_id for now)
      // In production, you would use the actual driver_id from your database
      final response = await supabase
          .from('deliveries')
          .select('*')
          // .eq('driver_id', user?.id)  // Uncomment when you have driver_id
          .order('scheduled_date', ascending: true);

      setState(() {
        deliveries = List<Map<String, dynamic>>.from(response);
        // Count pending and completed
        pendingCount = deliveries.where((d) => d['status'] != 'delivered').length;
        completedCount = deliveries.where((d) => d['status'] == 'delivered').length;
        isLoading = false;
      });
        } catch (e) {
      print('Error fetching deliveries: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Milk Delivery - Driver'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await supabase.auth.signOut();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: fetchDeliveries,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : deliveries.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No deliveries assigned',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Stats Cards
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.orange.shade200),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '$pendingCount',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                    const Text('Pending',
                                        style: TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.green.shade200),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '$completedCount',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                    const Text('Completed',
                                        style: TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Deliveries List
                      Expanded(
                        child: ListView.builder(
                          itemCount: deliveries.length,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemBuilder: (context, index) {
                            final delivery = deliveries[index];
                            final status = delivery['status'] ?? 'pending';
                            final isDelivered = status == 'delivered';
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isDelivered
                                      ? Colors.green
                                      : Colors.orange,
                                  child: Icon(
                                    isDelivered
                                        ? Icons.check
                                        : Icons.local_shipping,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                  'Delivery #${delivery['id'].toString().substring(0, 8)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  'Status: $status\n${delivery['scheduled_date'] ?? 'Today'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: isDelivered
                                    ? const Icon(Icons.check_circle,
                                        color: Colors.green)
                                    : const Icon(Icons.pending,
                                        color: Colors.orange),
                                onTap: () {
                                  // TODO: Navigate to delivery details
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Delivery ${delivery['id']} details coming soon!',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: fetchDeliveries,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}