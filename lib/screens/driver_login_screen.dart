import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:local_auth/local_auth.dart';
import 'package:milk_delivery/screens/driver_dashboard.dart'; // <-- added import

class DriverLoginScreen extends StatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  final supabase = Supabase.instance.client;
  bool _isScanning = false;
  bool _isLoading = false;
  String? _scannedBarcode;
  Map<String, dynamic>? _driverProfile;

  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  bool _obscurePin = true;

  bool get _isMobile => defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (_isMobile) _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    try {
      final localAuth = LocalAuthentication();
      final canCheck = await localAuth.canCheckBiometrics;
      final isAvailable = await localAuth.isDeviceSupported();
      print('Biometrics available: $canCheck, supported: $isAvailable');
    } catch (e) {
      print('Biometrics not supported: $e');
    }
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_isScanning) return;
    final String? barcode = capture.barcodes.first.rawValue;
    if (barcode != null) {
      setState(() {
        _isScanning = true;
        _scannedBarcode = barcode;
        _barcodeController.text = barcode;
      });
      _lookupDriver(barcode);
    }
  }

  Future<void> _lookupDriver(String barcodeId) async {
    // For now, we'll use a hardcoded driver UUID to bypass barcode lookup.
    // Replace this with the actual barcode lookup later.
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('profiles')
          .select('*')
          .eq('id', 'c4a8f585-57cf-46b4-b107-7980c8f0e90b') // your driver ID
          .maybeSingle();

      if (response == null) {
        _showError('Driver not found. Please contact admin.');
        setState(() {
          _isLoading = false;
          _isScanning = false;
          _scannedBarcode = null;
          _barcodeController.clear();
        });
        return;
      }

      if (response['is_active'] != true) {
        _showError('Driver account is deactivated.');
        setState(() {
          _isLoading = false;
          _isScanning = false;
          _scannedBarcode = null;
          _barcodeController.clear();
        });
        return;
      }

      setState(() {
        _driverProfile = response;
        _isLoading = false;
      });

      if (_driverProfile!['pin_hash'] != null) {
        _showPinEntry();
      } else {
        _showCreatePin();
      }
    } catch (e) {
      _showError('Error: $e');
      setState(() {
        _isLoading = false;
        _isScanning = false;
        _scannedBarcode = null;
        _barcodeController.clear();
      });
    }
  }

  void _showCreatePin() {
    _pinController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Create PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Set a 4-6 digit PIN for future logins.'),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              obscureText: _obscurePin,
              decoration: InputDecoration(
                labelText: 'New PIN',
                suffixIcon: IconButton(
                  icon: Icon(_obscurePin ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePin = !_obscurePin),
                ),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              final pin = _pinController.text.trim();
              if (pin.length < 4 || pin.length > 6) {
                _showError('PIN must be 4-6 digits');
                return;
              }
              await supabase
                  .from('profiles')
                  .update({'pin_hash': pin})
                  .eq('id', _driverProfile!['id']);
              _showSuccess('PIN created successfully!');
              Navigator.pop(context);
              _navigateToDriverDashboard(); // <-- calls helper
            },
            child: const Text('Set PIN'),
          ),
        ],
      ),
    );
  }

  void _showPinEntry() {
    _pinController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Enter PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your PIN to continue.'),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              obscureText: _obscurePin,
              decoration: InputDecoration(
                labelText: 'PIN',
                suffixIcon: IconButton(
                  icon: Icon(_obscurePin ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePin = !_obscurePin),
                ),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              final enteredPin = _pinController.text.trim();
              final storedPin = _driverProfile!['pin_hash'];
              if (enteredPin == storedPin) {
                _showSuccess('Login successful!');
                Navigator.pop(context);
                _navigateToDriverDashboard(); // <-- calls helper
              } else {
                _showError('Incorrect PIN');
              }
            },
            child: const Text('Login'),
          ),
          if (_isMobile && _driverProfile?['pin_hash'] != null)
            TextButton(
              onPressed: _authenticateWithBiometrics,
              child: const Text('Use Fingerprint'),
            ),
        ],
      ),
    );
  }

  Future<void> _authenticateWithBiometrics() async {
    try {
      final localAuth = LocalAuthentication();
      final authenticated = await localAuth.authenticate(
        localizedReason: 'Scan your fingerprint to login',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (authenticated) {
        _showSuccess('Fingerprint verified!');
        Navigator.pop(context);
        _navigateToDriverDashboard(); // <-- calls helper
      } else {
        _showError('Fingerprint not recognized');
      }
    } catch (e) {
      _showError('Biometric error: $e');
    }
  }

  // Helper to navigate with driver ID
  void _navigateToDriverDashboard() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DriverDashboard(
          driverId: _driverProfile!['id'], // <-- pass the ID
        ),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Login'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _scannedBarcode == null
              ? Column(
                  children: [
                    if (_isMobile)
                      Expanded(
                        flex: 2,
                        child: MobileScanner(
                          onDetect: _onBarcodeDetected,
                          controller: MobileScannerController(
                            detectionSpeed: DetectionSpeed.normal,
                            facing: CameraFacing.back,
                          ),
                          placeholderBuilder: (context, child) => const Center(
                            child: Text(
                              'Point camera at QR code',
                              style: TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                          ),
                        ),
                      )
                    else
                      const Expanded(
                        flex: 2,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.qr_code, size: 80, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'Camera not available on desktop.',
                                style: TextStyle(fontSize: 16, color: Colors.grey),
                              ),
                              Text(
                                'Please type your barcode ID below.',
                                style: TextStyle(fontSize: 14, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _barcodeController,
                              decoration: const InputDecoration(
                                labelText: 'Enter Barcode ID',
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (value) {
                                if (value.isNotEmpty) _lookupDriver(value.trim());
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              final barcode = _barcodeController.text.trim();
                              if (barcode.isNotEmpty) _lookupDriver(barcode);
                            },
                            child: const Text('Submit'),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle, size: 80, color: Colors.green),
                      const SizedBox(height: 16),
                      Text('Scanned: $_scannedBarcode'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _scannedBarcode = null;
                            _isScanning = false;
                            _driverProfile = null;
                            _pinController.clear();
                            _barcodeController.clear();
                          });
                        },
                        child: const Text('Scan Again'),
                      ),
                    ],
                  ),
                ),
    );
  }
}