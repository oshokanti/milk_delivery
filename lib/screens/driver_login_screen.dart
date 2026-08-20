import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:local_auth/local_auth.dart';
import 'package:milk_delivery/screens/driver_dashboard.dart';

class DriverLoginScreen extends StatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  final supabase = Supabase.instance.client;
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _isScanning = false;
  bool _isLoading = false;
  String? _scannedBarcode;
  Map<String, dynamic>? _driverProfile;

  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  bool _obscurePin = true;

  bool _biometricAvailable = false;
  String _biometricType = 'Biometrics';

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isAvailable = await _localAuth.isDeviceSupported();
      if (canCheck && isAvailable) {
        final availableBiometrics = await _localAuth.getAvailableBiometrics();
        if (availableBiometrics.isNotEmpty) {
          setState(() {
            _biometricAvailable = true;
            if (availableBiometrics.contains(BiometricType.face)) {
              _biometricType = 'Face ID';
            } else if (availableBiometrics.contains(BiometricType.fingerprint)) {
              _biometricType = 'Fingerprint';
            } else if (availableBiometrics.contains(BiometricType.iris)) {
              _biometricType = 'Iris';
            } else {
              _biometricType = 'Biometrics';
            }
          });
        }
      }
    } catch (e) {
      print('Biometric availability check failed: $e');
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
    setState(() => _isLoading = true);
    print('🔍 Looking up barcode: "$barcodeId"');
    try {
      final response = await supabase
          .from('profiles')
          .select('*')
          .eq('barcode_id', barcodeId)
          .eq('role', 'driver')
          .maybeSingle();

      print('📦 Response: $response');

      if (response == null) {
        _showError('Invalid barcode. Please contact admin.');
        setState(() {
          _isScanning = false;
          _isLoading = false;
          _scannedBarcode = null;
          _barcodeController.clear();
        });
        return;
      }

      if (response['is_active'] != true) {
        _showError('Driver account is deactivated. Contact admin.');
        setState(() {
          _isScanning = false;
          _isLoading = false;
          _scannedBarcode = null;
          _barcodeController.clear();
        });
        return;
      }

      setState(() {
        _driverProfile = response;
        _isLoading = false;
      });

      // Check if PIN is set
      final storedPin = _driverProfile!['pin_hash'];
      print('🔑 Stored PIN hash: $storedPin');

      if (storedPin == null || storedPin.isEmpty) {
        // First login – create PIN
        _showCreatePin();
      } else {
        _showPinEntry();
      }
    } catch (e) {
      print('❌ Error: $e');
      _showError('Error: $e');
      setState(() {
        _isScanning = false;
        _isLoading = false;
        _scannedBarcode = null;
        _barcodeController.clear();
      });
    }
  }

  // ----- Create PIN (first login) -----
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
              try {
                // Store PIN (plain text for demo – hash in production)
                await supabase
                    .from('profiles')
                    .update({'pin_hash': pin})
                    .eq('id', _driverProfile!['id']);
                print('✅ PIN saved for driver ${_driverProfile!['id']}');
                _showSuccess('PIN created successfully!');
                Navigator.pop(context);
                _navigateToDriverDashboard();
              } catch (e) {
                print('❌ Error saving PIN: $e');
                _showError('Error saving PIN: $e');
              }
            },
            child: const Text('Set PIN'),
          ),
        ],
      ),
    );
  }

  // ----- Enter PIN (existing driver) -----
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
              print('🔐 Entered PIN: $enteredPin, Stored: $storedPin');
              if (enteredPin == storedPin) {
                _showSuccess('Login successful!');
                Navigator.pop(context);
                _navigateToDriverDashboard();
              } else {
                _showError('Incorrect PIN');
              }
            },
            child: const Text('Login'),
          ),
          if (_biometricAvailable)
            TextButton(
              onPressed: _authenticateWithBiometrics,
              child: Text('Use $_biometricType'),
            ),
        ],
      ),
    );
  }

  // ----- Biometric authentication -----
  Future<void> _authenticateWithBiometrics() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Scan your fingerprint or use face recognition to login',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (authenticated) {
        _showSuccess('$_biometricType verified!');
        Navigator.pop(context); // close PIN dialog
        _navigateToDriverDashboard();
      } else {
        _showError('$_biometricType not recognized');
      }
    } catch (e) {
      _showError('Biometric error: $e');
    }
  }

  // ----- Navigation (clears stack) -----
  void _navigateToDriverDashboard() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => DriverDashboard(
          driverId: _driverProfile!['id'],
        ),
      ),
      (route) => false,
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

  // ----- UI -----
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
                    if (defaultTargetPlatform == TargetPlatform.android ||
                        defaultTargetPlatform == TargetPlatform.iOS)
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