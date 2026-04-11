import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:boomprint/printer_url_formats.dart';

import 'settings_manager.dart';
import 'window_drag_controller.dart';

class SettingsPage extends StatefulWidget {
  final Function(String)? onConnect; // Callback for connect button

  const SettingsPage({super.key, this.onConnect});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController specialCodeController = TextEditingController();
  final TextEditingController printerIpController = TextEditingController();
  final TextEditingController serialNumberController =
      TextEditingController(); // <-- Added
  final TextEditingController genericRtspUsernameController =
      TextEditingController();
  final TextEditingController genericRtspPasswordController =
      TextEditingController();
  final TextEditingController genericRtspPathController =
      TextEditingController();
  final TextEditingController genericRtspPortController =
      TextEditingController();
  bool _autoConnect = false;
  bool _mqttControlsEnabled = false;
  bool _lightControlsEnabled = false;
  bool _hardwareAccelerationEnabled = true;
  bool _linuxUseSystemWindowDecorations = false;
  bool _genericRtspSecure = false;

  PrinterUrlType selectedFormat = PrinterUrlType.bambuX1C;

  final TextEditingController customUrlController = TextEditingController();

  bool get _supportsQrScan =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get _supportsLinuxSystemDecorations =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsManager.loadSettings();
    specialCodeController.text = settings.specialCode;
    printerIpController.text = settings.printerIp;
    serialNumberController.text = settings.serialNumber;
    customUrlController.text = settings.customUrl;
    genericRtspUsernameController.text = settings.genericRtspUsername;
    genericRtspPasswordController.text = settings.genericRtspPassword;
    genericRtspPathController.text = settings.genericRtspPath;
    genericRtspPortController.text = settings.genericRtspPort.toString();
    selectedFormat = settings.selectedFormat;
    _autoConnect = settings.autoConnect;
    _mqttControlsEnabled = settings.mqttControlsEnabled;
    _lightControlsEnabled = settings.lightControlsEnabled;
    _hardwareAccelerationEnabled = settings.hardwareAccelerationEnabled;
    _linuxUseSystemWindowDecorations = settings.linuxUseSystemWindowDecorations;
    _genericRtspSecure = settings.genericRtspSecure;
    setState(() {});
  }

  Future<void> _saveSettings() async {
    final settings = AppSettings(
      specialCode: specialCodeController.text,
      printerIp: printerIpController.text,
      serialNumber: serialNumberController.text,
      selectedFormat: selectedFormat,
      customUrl: customUrlController.text,
      genericRtspUsername: genericRtspUsernameController.text,
      genericRtspPassword: genericRtspPasswordController.text,
      genericRtspPath: genericRtspPathController.text,
      genericRtspPort: int.tryParse(genericRtspPortController.text) ?? 554,
      genericRtspSecure: _genericRtspSecure,
      autoConnect: _autoConnect,
      mqttControlsEnabled: _mqttControlsEnabled,
      lightControlsEnabled: _lightControlsEnabled,
      hardwareAccelerationEnabled: _hardwareAccelerationEnabled,
      linuxUseSystemWindowDecorations: _linuxUseSystemWindowDecorations,
    );
    await SettingsManager.saveSettings(settings);
    await WindowChromeController.setLinuxSystemDecorations(
      _linuxUseSystemWindowDecorations,
    );
  }

  Map<String, dynamic> _normalizeJson(Map<String, dynamic> src) {
    // Accept both new camelCase keys and legacy SharedPreferences-like keys
    final m = Map<String, dynamic>.from(src);
    String pick(String a, String b, [String fallback = '']) =>
        (m[a] ?? m[b] ?? fallback) as String;

    return {
      'specialCode': pick('specialCode', 'rtsp_specialcode'),
      'printerIp': pick('printerIp', 'rtsp_printerip'),
      'serialNumber': pick('serialNumber', 'rtsp_serial_number'),
      'selectedFormat': pick('selectedFormat', 'rtsp_format', 'Bambu X1C'),
      'customUrl': pick('customUrl', 'rtsp_custom_url'),
      'genericRtspUsername': pick(
        'genericRtspUsername',
        'rtsp_generic_username',
      ),
      'genericRtspPassword': pick(
        'genericRtspPassword',
        'rtsp_generic_password',
      ),
      'genericRtspPath': pick(
        'genericRtspPath',
        'rtsp_generic_path',
        '/stream',
      ),
      'genericRtspPort':
          (m['genericRtspPort'] ?? m['rtsp_generic_port'] ?? 554),
      'genericRtspSecure':
          (m['genericRtspSecure'] ?? m['rtsp_generic_secure'] ?? false),
      'autoConnect': (m['autoConnect'] ?? m['rtsp_auto_connect'] ?? false),
      'mqttControlsEnabled':
          (m['mqttControlsEnabled'] ??
          m['rtsp_mqtt_controls_enabled'] ??
          false),
      'lightControlsEnabled':
          (m['lightControlsEnabled'] ??
          m['rtsp_light_controls_enabled'] ??
          false),
      'hardwareAccelerationEnabled':
          (m['hardwareAccelerationEnabled'] ??
          m['rtsp_hardware_acceleration_enabled'] ??
          true),
      'linuxUseSystemWindowDecorations':
          (m['linuxUseSystemWindowDecorations'] ??
          m['rtsp_linux_use_system_window_decorations'] ??
          false),
    };
  }

  Future<void> _importFromJson() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true, // ensure bytes are available on all platforms
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.bytes == null) {
        // Shouldn't happen with withData: true, but guard anyway
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to read selected file.')),
        );
        return;
      }

      final content = utf8.decode(file.bytes!);
      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid settings JSON format.')),
        );
        return;
      }

      final normalized = _normalizeJson(decoded);
      final imported = AppSettings.fromJson(normalized);

      // Update UI fields
      setState(() {
        specialCodeController.text = imported.specialCode;
        printerIpController.text = imported.printerIp;
        serialNumberController.text = imported.serialNumber;
        customUrlController.text = imported.customUrl;
        genericRtspUsernameController.text = imported.genericRtspUsername;
        genericRtspPasswordController.text = imported.genericRtspPassword;
        genericRtspPathController.text = imported.genericRtspPath;
        genericRtspPortController.text = imported.genericRtspPort.toString();
        selectedFormat = imported.selectedFormat;
        _genericRtspSecure = imported.genericRtspSecure;
        _autoConnect = imported.autoConnect;
        _mqttControlsEnabled = imported.mqttControlsEnabled;
        _lightControlsEnabled = imported.lightControlsEnabled;
        _hardwareAccelerationEnabled = imported.hardwareAccelerationEnabled;
        _linuxUseSystemWindowDecorations =
            imported.linuxUseSystemWindowDecorations;
      });

      // Persist via manager (writes SharedPreferences & JSON file)
      await SettingsManager.saveSettings(imported);

      if (mounted) {
        final origin = file.path?.isNotEmpty == true ? file.path : file.name;
        final msg = origin != null && origin.isNotEmpty
            ? 'Settings imported from: $origin'
            : 'Settings imported successfully.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  Future<void> _exportToJson() async {
    try {
      // Compose settings from current UI state so unsaved edits are included
      final settings = AppSettings(
        specialCode: specialCodeController.text,
        printerIp: printerIpController.text,
        serialNumber: serialNumberController.text,
        selectedFormat: selectedFormat,
        customUrl: customUrlController.text,
        genericRtspUsername: genericRtspUsernameController.text,
        genericRtspPassword: genericRtspPasswordController.text,
        genericRtspPath: genericRtspPathController.text,
        genericRtspPort: int.tryParse(genericRtspPortController.text) ?? 554,
        genericRtspSecure: _genericRtspSecure,
        autoConnect: _autoConnect,
        mqttControlsEnabled: _mqttControlsEnabled,
        lightControlsEnabled: _lightControlsEnabled,
        hardwareAccelerationEnabled: _hardwareAccelerationEnabled,
        linuxUseSystemWindowDecorations: _linuxUseSystemWindowDecorations,
      );

      final jsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(settings.toJson());
      final bytes = Uint8List.fromList(utf8.encode(jsonString));

      final savedPath = await FileSaver.instance.saveFile(
        name: 'boomprint_settings',
        fileExtension: 'json',
        bytes: bytes,
        mimeType: MimeType.json,
      );

      if (mounted) {
        final text = (savedPath.toString().trim().isNotEmpty)
            ? 'Settings exported to: $savedPath'
            : 'Settings exported to JSON.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Map<String, String> _extractQrFields(String raw) {
    final out = <String, String>{};
    final text = raw.trim();
    if (text.isEmpty) return out;

    String? _pick(Map<String, dynamic> m, List<String> keys) {
      for (final key in keys) {
        final v = m[key];
        if (v != null && v.toString().trim().isNotEmpty) {
          return v.toString().trim();
        }
      }
      return null;
    }

    void _applyMap(Map<String, dynamic> map) {
      final specialCode = _pick(map, const [
        'specialCode',
        'special_code',
        'accessCode',
        'access_code',
        'token',
        'code',
      ]);
      final printerIp = _pick(map, const [
        'printerIp',
        'printer_ip',
        'ip',
        'host',
        'address',
      ]);
      final serial = _pick(map, const [
        'serialNumber',
        'serial_number',
        'serial',
        'sn',
        'device_sn',
      ]);
      if (specialCode != null) out['specialCode'] = specialCode;
      if (printerIp != null) out['printerIp'] = printerIp;
      if (serial != null) out['serialNumber'] = serial;
    }

    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          _applyMap(decoded);
        }
      } catch (_) {}
    }

    final uri = Uri.tryParse(text);
    if (uri != null) {
      final qp = <String, dynamic>{};
      for (final entry in uri.queryParameters.entries) {
        qp[entry.key] = entry.value;
      }
      _applyMap(qp);
    }

    if (out.isEmpty) {
      final kv = <String, dynamic>{};
      final parts = text.split(RegExp(r'[;\n,&]'));
      for (final p in parts) {
        final idx = p.indexOf('=');
        if (idx <= 0) continue;
        final k = p.substring(0, idx).trim();
        final v = p.substring(idx + 1).trim();
        if (k.isNotEmpty && v.isNotEmpty) kv[k] = v;
      }
      if (kv.isNotEmpty) _applyMap(kv);
    }

    if (!out.containsKey('printerIp')) {
      final m = RegExp(r'(\d{1,3}\.){3}\d{1,3}').firstMatch(text);
      if (m != null) out['printerIp'] = m.group(0)!;
    }

    return out;
  }

  Future<void> _scanQrConfig() async {
    if (!_supportsQrScan) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR scanning is available on mobile only.'),
        ),
      );
      return;
    }

    final raw = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _QrScanPage()));
    if (!mounted || raw == null || raw.trim().isEmpty) return;

    final parsed = _extractQrFields(raw);
    if (parsed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR scanned, but no known config fields found.'),
        ),
      );
      return;
    }

    setState(() {
      final code = parsed['specialCode'];
      final ip = parsed['printerIp'];
      final sn = parsed['serialNumber'];
      if (code != null) specialCodeController.text = code;
      if (ip != null) printerIpController.text = ip;
      if (sn != null) serialNumberController.text = sn;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Applied printer fields from QR code.')),
    );
  }

  String _generateUrl() {
    if (selectedFormat == PrinterUrlType.custom) {
      return customUrlController.text;
    }
    if (selectedFormat == PrinterUrlType.genericRtsp) {
      final host = printerIpController.text.trim();
      final port = int.tryParse(genericRtspPortController.text.trim()) ?? 554;
      final rawPath = genericRtspPathController.text.trim().isEmpty
          ? '/stream'
          : genericRtspPathController.text.trim();
      final normalizedPath = rawPath.startsWith('/') ? rawPath : '/$rawPath';
      final scheme = _genericRtspSecure ? 'rtsps' : 'rtsp';
      final user = genericRtspUsernameController.text.trim();
      final pass = genericRtspPasswordController.text;
      final userInfo = user.isEmpty
          ? ''
          : '${Uri.encodeComponent(user)}:${Uri.encodeComponent(pass)}@';
      return '$scheme://$userInfo$host:$port$normalizedPath';
    }
    final template = selectedFormat.template;
    return template
        .replaceAll('\${specialcode}', specialCodeController.text)
        .replaceAll('\${printerip}', printerIpController.text);
  }

  @override
  Widget build(BuildContext context) {
    return FramelessWindowResizeFrame(
      child: Scaffold(
        appBar: AppBar(
          title: const WindowDragArea(
            child: SizedBox(
              width: double.infinity,
              child: Text('Stream Settings'),
            ),
          ),
          actions: [
            if (_supportsQrScan)
              IconButton(
                tooltip: 'Scan printer QR',
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: _scanQrConfig,
              ),
            IconButton(
              tooltip: 'Export settings to JSON',
              icon: const Icon(Icons.file_download),
              onPressed: _exportToJson,
            ),
            IconButton(
              tooltip: 'Import settings from JSON',
              icon: const Icon(Icons.file_open),
              onPressed: _importFromJson,
            ),
            const WindowControlButtons(),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'URL Format:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButton<PrinterUrlType>(
                      value: selectedFormat,
                      isExpanded: true,
                      items: PrinterUrlType.values
                          .map(
                            (t) => DropdownMenuItem<PrinterUrlType>(
                              value: t,
                              child: Text(t.displayName),
                            ),
                          )
                          .toList(),
                      onChanged: (PrinterUrlType? newValue) {
                        setState(() {
                          selectedFormat = newValue!;
                        });
                      },
                    ),
                    const SizedBox(height: 20),

                    // Show template variable inputs for Bambu X1C format
                    if (selectedFormat == PrinterUrlType.bambuX1C ||
                        selectedFormat == PrinterUrlType.bambuP1S) ...[
                      TextFormField(
                        controller: specialCodeController,
                        decoration: const InputDecoration(
                          labelText: 'Special Code',
                          hintText: 'Enter your printer\'s special code',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter the special code';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: printerIpController,
                        decoration: const InputDecoration(
                          labelText: 'Printer IP Address',
                          hintText: 'e.g., 192.168.1.100',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter the printer IP address';
                          }
                          // Basic IP validation
                          final ipRegExp = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
                          if (!ipRegExp.hasMatch(value)) {
                            return 'Please enter a valid IP address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: serialNumberController,
                        decoration: const InputDecoration(
                          labelText: 'Serial Number',
                          hintText: 'Enter your printer\'s serial number',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter the serial number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Generated URL will be:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _generateUrl(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],

                    if (selectedFormat == PrinterUrlType.genericRtsp) ...[
                      TextFormField(
                        controller: printerIpController,
                        decoration: const InputDecoration(
                          labelText: 'RTSP Host / IP Address',
                          hintText: 'e.g., 192.168.1.100',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter the RTSP host or IP address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: genericRtspPortController,
                        decoration: const InputDecoration(
                          labelText: 'RTSP Port',
                          hintText: '554',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final port = int.tryParse((value ?? '').trim());
                          if (port == null || port < 1 || port > 65535) {
                            return 'Please enter a valid port';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: genericRtspPathController,
                        decoration: const InputDecoration(
                          labelText: 'Stream Path',
                          hintText: '/stream',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter the RTSP path';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: genericRtspUsernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          hintText: 'Optional RTSP username',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: genericRtspPasswordController,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          hintText: 'Optional RTSP password',
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Use secure RTSP (RTSPS)'),
                        subtitle: const Text(
                          'Switch between rtsp:// and rtsps:// transport.',
                        ),
                        value: _genericRtspSecure,
                        onChanged: (v) =>
                            setState(() => _genericRtspSecure = v),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Generated URL will be:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _generateUrl(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],

                    // Show custom URL input for Custom format
                    if (selectedFormat == PrinterUrlType.custom) ...[
                      TextFormField(
                        controller: customUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Custom RTSP URL',
                          hintText: 'Enter your custom RTSP URL',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a custom RTSP URL';
                          }
                          if (!value.startsWith('rtsp://') &&
                              !value.startsWith('rtsps://')) {
                            return 'URL must start with rtsp:// or rtsps://';
                          }
                          return null;
                        },
                      ),
                    ],

                    const SizedBox(height: 30),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-connect on launch'),
                      subtitle: const Text(
                        'Automatically connect when this config is valid.',
                      ),
                      value: _autoConnect,
                      onChanged: (v) => setState(() => _autoConnect = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable MQTT controls'),
                      subtitle: const Text(
                        'Show advanced MQTT control panel (use with care).',
                      ),
                      value: _mqttControlsEnabled,
                      onChanged: (v) =>
                          setState(() => _mqttControlsEnabled = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable hardware video acceleration'),
                      subtitle: const Text(
                        'Disable to force software decoding/rendering.',
                      ),
                      value: _hardwareAccelerationEnabled,
                      onChanged: (v) =>
                          setState(() => _hardwareAccelerationEnabled = v),
                    ),
                    if (_supportsLinuxSystemDecorations)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Use system window decorations'),
                        subtitle: const Text(
                          'Try native Linux title bars and compositor-provided rounded corners.',
                        ),
                        value: _linuxUseSystemWindowDecorations,
                        onChanged: (v) => setState(
                          () => _linuxUseSystemWindowDecorations = v,
                        ),
                      ),
                    const SizedBox(height: 20),

                    Wrap(
                      alignment: WrapAlignment.center,
                      runAlignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            if (_formKey.currentState!.validate()) {
                              await _saveSettings();
                              if (mounted) {
                                Navigator.pop(context); // Just save and close
                              }
                            }
                          },
                          child: const Text('Save'),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            await _exportToJson();
                          },
                          child: const Text('Export'),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            await _importFromJson();
                          },
                          child: const Text('Import'),
                        ),
                        if (_supportsQrScan)
                          ElevatedButton(
                            onPressed: _scanQrConfig,
                            child: const Text('Scan QR'),
                          ),
                        ElevatedButton(
                          onPressed: () async {
                            if (_formKey.currentState!.validate()) {
                              await _saveSettings();
                              final generatedUrl = _generateUrl();
                              if (mounted && widget.onConnect != null) {
                                widget.onConnect!(generatedUrl);
                              }
                              if (mounted) {
                                Navigator.pop(
                                  context,
                                ); // Close settings and connect
                              }
                            }
                          },
                          child: const Text('Connect'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QrScanPage extends StatefulWidget {
  const _QrScanPage();

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Printer QR')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          for (final code in capture.barcodes) {
            final value = code.rawValue?.trim();
            if (value != null && value.isNotEmpty) {
              _handled = true;
              Navigator.of(context).pop(value);
              break;
            }
          }
        },
      ),
    );
  }
}
