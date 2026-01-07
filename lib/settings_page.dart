import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:rnd_bambu_rtsp_stream/printer_url_formats.dart';

import 'settings_manager.dart';

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

  PrinterUrlType selectedFormat = PrinterUrlType.bambuX1C;

  final TextEditingController customUrlController = TextEditingController();

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
    selectedFormat = settings.selectedFormat;
    setState(() {});
  }

  Future<void> _saveSettings() async {
    final settings = AppSettings(
      specialCode: specialCodeController.text,
      printerIp: printerIpController.text,
      serialNumber: serialNumberController.text,
      selectedFormat: selectedFormat,
      customUrl: customUrlController.text,
    );
    await SettingsManager.saveSettings(settings);
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
        selectedFormat = imported.selectedFormat;
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
      );

      final jsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(settings.toJson());
      final bytes = Uint8List.fromList(utf8.encode(jsonString));

      final savedPath = await FileSaver.instance.saveFile(
        name: 'rtsp_settings',
        fileExtension: 'json',
        bytes: bytes,
        mimeType: MimeType.json,
      );

      if (mounted) {
        final text =
            (savedPath != null && savedPath.toString().trim().isNotEmpty)
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

  String _generateUrl() {
    if (selectedFormat == PrinterUrlType.custom) {
      return customUrlController.text;
    }
    final template = selectedFormat.template;
    return template
        .replaceAll('\${specialcode}', specialCodeController.text)
        .replaceAll('\${printerip}', printerIpController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stream Settings'),
        actions: [
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
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'URL Format:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              if (selectedFormat == PrinterUrlType.bambuX1C) ...[
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
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                Text(
                  _generateUrl(),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
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

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                  ElevatedButton(
                    onPressed: () async {
                      if (_formKey.currentState!.validate()) {
                        await _saveSettings();
                        final generatedUrl = _generateUrl();
                        if (mounted && widget.onConnect != null) {
                          widget.onConnect!(generatedUrl);
                        }
                        if (mounted) {
                          Navigator.pop(context); // Close settings and connect
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
    );
  }
}
