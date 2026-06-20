import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cbor/cbor.dart';
import 'package:pointycastle/export.dart' as pc;
import 'crypto.dart';
import 'protocol.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Siros Verifier',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A2540),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

// ── Splash Screen ─────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeIn;
  late Animation<double> _slideUp;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _fadeIn = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _slideUp = Tween<double>(begin: 30, end: 0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A2540),
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Opacity(
            opacity: _fadeIn.value,
            child: Transform.translate(
              offset: Offset(0, _slideUp.value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.2), width: 1),
                    ),
                    child: const Icon(Icons.verified_user_rounded,
                        color: Colors.white, size: 48),
                  ),
                  const SizedBox(height: 28),
                  const Text('SIROS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 8,
                      )),
                  const SizedBox(height: 6),
                  Text('VERIFIER',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 6,
                      )),
                  const SizedBox(height: 64),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Home Screen ───────────────────────────────────────────────────────────────

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: const Color(0xFF0A2540),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.verified_user_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SIROS VERIFIER',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2)),
                      Text('ISO 18013-5 mDL',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A2540).withOpacity(0.06),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.qr_code_scanner_rounded,
                            size: 56, color: Color(0xFF0A2540)),
                      ),
                      const SizedBox(height: 28),
                      const Text('Verify a driving licence',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0A2540),
                          )),
                      const SizedBox(height: 10),
                      Text(
                        'Scan the QR code displayed on the\nholder\'s device to begin verification.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            height: 1.5),
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.qr_code_rounded, size: 20),
                          label: const Text('Scan QR Code',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0A2540),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(
                                  builder: (_) => const ScanScreen())),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text('Secure · Privacy-preserving · ISO compliant',
                  style:
                  TextStyle(fontSize: 11, color: Colors.grey[400])),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Scan Screen ───────────────────────────────────────────────────────────────

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.bluetoothAdvertise.request();
    await Permission.location.request();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null) return;
    final value = barcode.rawValue ?? '';
    if (!value.startsWith('mdoc:')) return;
    setState(() => _scanned = true);
    _controller.stop();
    final b64 = value.substring(5);
    final deBytes = base64Url.decode(base64Url.normalize(b64));
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => ConnectScreen(deBytes: Uint8List.fromList(deBytes)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2540),
        foregroundColor: Colors.white,
        title: const Text('Scan QR Code',
            style: TextStyle(fontWeight: FontWeight.w600)),
        elevation: 0,
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Text('Point at the mDL QR code',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.8), fontSize: 14)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

// ── Connect Screen ────────────────────────────────────────────────────────────

class ConnectScreen extends StatefulWidget {
  final Uint8List deBytes;
  const ConnectScreen({super.key, required this.deBytes});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  String _status = 'Initialising...';
  String _substatus = '';
  bool _isError = false;
  bool _done = false;
  static const _platform = MethodChannel('com.example.siros/ble');
  String? _targetUuid;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _setStatus(String s, [String sub = '']) {
    debugPrint('STATUS: $s $sub');
    if (mounted) {
      setState(() {
        _status = s;
        _substatus = sub;
        _isError = false;
      });
    }
  }

  void _setError(String s) {
    debugPrint('ERROR: $s');
    if (mounted) {
      setState(() {
        _status = 'Error';
        _substatus = s;
        _isError = true;
      });
    }
  }

  Future<void> _connect() async {
    try {
      _setStatus('Reading QR code', 'Parsing device engagement...');
      _targetUuid = extractUuid(widget.deBytes);
      debugPrint('deBytes: ${widget.deBytes.map((b) => b.toRadixString(16).padLeft(2,'0')).join()}');
      final eDeviceKeyBytes = extractEDeviceKey(widget.deBytes);

      _setStatus('Generating keys', 'Creating ephemeral reader key...');
      final domainParams = pc.ECDomainParameters('prime256v1');
      final keyGen = pc.ECKeyGenerator();
      final rng = pc.FortunaRandom();
      final seedSource = Random.secure();
      final seed = Uint8List(32);
      for (var i = 0; i < 32; i++) seed[i] = seedSource.nextInt(256);
      rng.seed(pc.KeyParameter(seed));
      keyGen.init(pc.ParametersWithRandom(
          pc.ECKeyGeneratorParameters(domainParams), rng));
      final keyPair = keyGen.generateKeyPair();
      final eReaderPrivKey = keyPair.privateKey as pc.ECPrivateKey;
      final eReaderPubKey = keyPair.publicKey as pc.ECPublicKey;
      final eReaderPubKeyBytes =
      Uint8List.fromList(eReaderPubKey.Q!.getEncoded(false));

      final eReaderKeyCose = buildCoseKey(eReaderPubKeyBytes);
      final sessionTranscript =
      buildSessionTranscript(widget.deBytes, eReaderKeyCose);
      final sharedSecret =
      ecdhSharedSecret(eReaderPrivKey, eDeviceKeyBytes);
      final skReader = deriveSKReader(sharedSecret, sessionTranscript);
      final deviceRequest = buildDeviceRequest();
      debugPrint('sessionTranscript: ${sessionTranscript.map((b) => b.toRadixString(16).padLeft(2,'0')).join()}');



      // Encrypt with SKReader - reader role identifier=0, counter=1
      final iv = Uint8List(12);
      ByteData.view(iv.buffer).setUint32(4, 0, Endian.big); // reader = 0
      ByteData.view(iv.buffer).setUint32(8, 1, Endian.big); // counter = 1
      final encryptedRequest = aesGcmEncrypt(skReader, iv, deviceRequest);

      // SessionEstablishment with string keys matching multipaz format
      final sessionEstablishment =
      buildSessionEstablishment(eReaderKeyCose, encryptedRequest);
      debugPrint('SE hex: ${sessionEstablishment.map((b) => b.toRadixString(16).padLeft(2,'0')).join()}');

      debugPrint('eReaderKeyCose: ${eReaderKeyCose.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');

      _setStatus('Advertising', 'Waiting for holder\'s device...');

      debugPrint('sharedSecret: ${sharedSecret.map((b) => b.toRadixString(16).padLeft(2,'0')).join()}');
      debugPrint('salt: ${saltFromTranscript(sessionTranscript).map((b) => b.toRadixString(16).padLeft(2,'0')).join()}');
      debugPrint('SKReader: ${skReader.map((b) => b.toRadixString(16).padLeft(2,'0')).join()}');
      debugPrint('IV: ${iv.map((b) => b.toRadixString(16).padLeft(2,'0')).join()}');
      debugPrint('encryptedRequest first 32: ${encryptedRequest.sublist(0,32).map((b) => b.toRadixString(16).padLeft(2,'0')).join()}');

      await _platform.invokeMethod<String>(
        'advertiseAndWait',
        {
          'uuid': _targetUuid,
          'eReaderKeyCose': eReaderKeyCose,
        },
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () =>
        throw Exception('Holder did not connect in time'),
      );

      _setStatus('Connected', 'Sending credential request...');
      await _platform.invokeMethod('sendData', {'data': sessionEstablishment});

      await Future.delayed(const Duration(milliseconds: 200));

      _setStatus('Waiting', 'Receiving credential data...');
      final response = await _platform.invokeMethod<Uint8List>(
        'waitForResponse',
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('No response from holder'),
      );

      if (response != null && response.isNotEmpty) {
        _setStatus('Decrypting', 'Verifying credential...');

        try {
          final sessionDataMap = cbor.decode(response) as CborMap;
          final encryptedData = Uint8List.fromList(
              (sessionDataMap[CborString('data')] as CborBytes).bytes);

          final skDevice = deriveSKDevice(sharedSecret, sessionTranscript);

          final ivCombinations = [
            [0, 0], [0, 1], [1, 0], [1, 1],
          ];

          Uint8List? plain;
          for (final combo in ivCombinations) {
            try {
              final ivDev = Uint8List(12);
              ByteData.view(ivDev.buffer)
                  .setUint32(4, combo[0], Endian.big);
              ByteData.view(ivDev.buffer)
                  .setUint32(8, combo[1], Endian.big);
              plain = aesGcmDecrypt(skDevice, ivDev, encryptedData);
              debugPrint(
                  '✅ Decrypted id=${combo[0]} counter=${combo[1]}');
              break;
            } catch (_) {}
          }

          if (plain == null || plain.isEmpty) {
            throw Exception('Decryption failed — try scanning again');
          }

          final fields = parseCredentials(plain);
          if (fields.isEmpty) {
            throw Exception('No credential fields found');
          }

          setState(() => _done = true);
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (_) => ResultScreen(fields: fields)),
            );
          }
        } catch (e) {
          _setError(
              'Parse error — please try again.\n${e.toString().replaceFirst('Exception: ', '')}');
        }
      } else {
        _setError('Empty response — please try again');
      }
    } catch (e) {
      _setError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2540),
        foregroundColor: Colors.white,
        title: const Text('Verifying',
            style: TextStyle(fontWeight: FontWeight.w600)),
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _isError
                      ? Colors.red.withOpacity(0.08)
                      : const Color(0xFF0A2540).withOpacity(0.06),
                  shape: BoxShape.circle,
                ),
                child: _isError
                    ? const Icon(Icons.error_outline_rounded,
                    color: Colors.red, size: 40)
                    : const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Color(0xFF0A2540)),
                ),
              ),
              const SizedBox(height: 28),
              Text(_status,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _isError
                          ? Colors.red
                          : const Color(0xFF0A2540))),
              if (_substatus.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_substatus,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        color: _isError
                            ? Colors.red[300]
                            : Colors.grey[500])),
              ],
              const SizedBox(height: 40),
              if (_isError)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const HomeScreen()),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0A2540),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Try Again',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                )
              else
                TextButton(
                  onPressed: () async {
                    await _platform.invokeMethod('stopAdvertise');
                    if (mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const HomeScreen()),
                      );
                    }
                  },
                  child: Text('Cancel',
                      style: TextStyle(color: Colors.grey[500])),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (!_done) _platform.invokeMethod('stopAdvertise');
    super.dispose();
  }
}

// ── Result Screen ─────────────────────────────────────────────────────────────

class ResultScreen extends StatelessWidget {
  final Map<String, String> fields;
  const ResultScreen({super.key, required this.fields});

  static const _labels = {
    'given_name': 'Given name',
    'family_name': 'Family name',
    'birth_date': 'Date of birth',
    'document_number': 'Document number',
    'issuing_country': 'Issuing country',
    'expiry_date': 'Expiry date',
    'issuing_authority': 'Issuing authority',
  };

  static const _icons = {
    'given_name': Icons.person_outline_rounded,
    'family_name': Icons.person_outline_rounded,
    'birth_date': Icons.cake_outlined,
    'document_number': Icons.badge_outlined,
    'issuing_country': Icons.flag_outlined,
    'expiry_date': Icons.calendar_today_outlined,
    'issuing_authority': Icons.account_balance_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final display = Map.fromEntries(fields.entries.where((e) =>
    e.key != 'portrait' &&
        e.value.isNotEmpty &&
        e.value != 'null'));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: const Color(0xFF0A2540),
              padding: const EdgeInsets.fromLTRB(8, 16, 20, 20),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const HomeScreen()),
                    ),
                  ),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Verification Result',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      Text('Mobile Driving Licence',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0A7A3C), Color(0xFF0DAF55)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0A7A3C).withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check_circle_rounded,
                                color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 16),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Credential Verified',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                              SizedBox(height: 2),
                              Text('ISO 18013-5 mDL · Proximity',
                                  style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Row(
                              children: [
                                const Icon(Icons.credit_card_rounded,
                                    size: 16, color: Color(0xFF0A2540)),
                                const SizedBox(width: 8),
                                Text('Identity Claims',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey[600],
                                        letterSpacing: 0.5)),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          ...display.entries.map((e) {
                            final label = _labels[e.key] ??
                                e.key.replaceAll('_', ' ');
                            final icon = _icons[e.key] ??
                                Icons.info_outline_rounded;
                            final isLast = e.key == display.keys.last;
                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 14),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0A2540)
                                              .withOpacity(0.06),
                                          borderRadius:
                                          BorderRadius.circular(10),
                                        ),
                                        child: Icon(icon,
                                            size: 18,
                                            color: const Color(0xFF0A2540)),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            Text(label,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[500],
                                                    fontWeight:
                                                    FontWeight.w500)),
                                            const SizedBox(height: 2),
                                            Text(e.value,
                                                style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight:
                                                    FontWeight.w600,
                                                    color:
                                                    Color(0xFF0A2540))),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isLast)
                                  const Divider(height: 1, indent: 70),
                              ],
                            );
                          }),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0A2540),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const HomeScreen()),
                        ),
                        child: const Text('Done',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Verified at ${_now()}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[400])),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _now() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')} · ${n.day}/${n.month}/${n.year}';
  }
}