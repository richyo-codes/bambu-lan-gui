// lib/bambu_lan.dart
// -------------------
// High-level LAN client for Bambu printers: MQTT (telemetry + control)
// and FTP/FTPS (SD-card file operations). Works in Dart VM / Flutter.
//
// Usage sketch (see example/main.dart below for a runnable snippet):
//   final lan = BambuLan(
//     config: BambuLanConfig(
//       printerIp: '192.168.1.50',
//       accessCode: 'YOUR_LAN_ACCESS_CODE',
//       serial: '00Mxxxxxxxxxxxx', // optional for wildcard sub
//       allowBadCerts: false,
//       // caCertPem: await rootBundle.loadString('assets/printer_ca.pem'),
//     ),
//   );
//   await lan.connect();
//   final sub = lan.reportStream.listen((e) { print('Report: ${e.type} ${e.json}'); });
//   final entries = await lan.ftp.list('/');
//   await lan.ftp.upload(localPath: 'job.3mf', remotePath: '/sdcard/job/job.3mf');
//   await lan.mqtt.startPrintFromSd('/sdcard/job/job.3mf');
//   ...

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_mqtt.dart';

// ============================
// Configuration & Public Types
// ============================

class BambuLanConfig {
  final String printerIp;
  final String accessCode; // LAN access code entered on the printer
  final String? serial; // Printer serial (USN); optional for wildcard subscribe

  /// If true, accept self-signed/unknown TLS certs for MQTT.
  /// Prefer providing [caCertPem] instead.
  final bool allowBadCerts;

  /// PEM text of the device CA cert (recommended). If provided, we'll use a
  /// custom SecurityContext trusting only this PEM.
  final String? caCertPem;

  /// MQTT port on the printer (default 8883 for TLS)
  final int mqttPort;

  /// FTP port (21). Use explicit TLS (FTPES) with [useFtps] if available.
  final int ftpPort;

  /// Use explicit TLS for FTP (aka FTPES). Falls back to plain FTP if the
  /// server doesn't support it.
  final bool useFtps;

  const BambuLanConfig({
    required this.printerIp,
    required this.accessCode,
    this.serial,
    this.allowBadCerts = true,
    this.caCertPem,
    this.mqttPort = 8883,
    this.ftpPort = 21,
    this.useFtps = true,
  });
}

/// Simple directory entry abstraction for FTP results.
class FtpEntry {
  final String name;
  final bool isDir;
  final int? size;
  final DateTime? modified;
  final String path;

  const FtpEntry({
    required this.name,
    required this.isDir,
    required this.path,
    this.size,
    this.modified,
  });
}

/// Report event wrapper for MQTT frames.
class BambuReportEvent {
  final String topic;
  final Map<String, dynamic> json;
  final String? type; // high-level message type or state
  final BambuPrintStatus?
  printStatus; // parsed metrics if this is a print report
  const BambuReportEvent({
    required this.topic,
    required this.json,
    this.type,
    this.printStatus,
  });
}

class BambuPrintStatus {
  final String gcodeState; // e.g. RUNNING, IDLE, FINISH
  final int? percent; // mc_percent 0..100
  final int? remainingMinutes; // mc_remaining_time (minutes)
  final String? gcodeFile; // gcode_file
  final int? layer; // layer_num
  final int? totalLayers; // total_layer_num
  final double? bedTemp; // bed_temper
  final double? bedTarget; // bed_target_temper
  final double? nozzleTemp; // nozzle_temper
  final double? nozzleTarget; // nozzle_target_temper
  final double? chamberTemp; // chamber_temper
  final String? nozzleType; // nozzle_type
  final String? nozzleDiameter; // nozzle_diameter
  final int? speedLevel; // spd_lvl
  final int? speedMag; // spd_mag
  final String? subtaskName; // subtask_name
  final String? taskId; // task_id
  final String? jobId; // job_id
  final String? wifiSignal; // wifi_signal, e.g. -48dBm

  const BambuPrintStatus({
    required this.gcodeState,
    this.percent,
    this.remainingMinutes,
    this.gcodeFile,
    this.layer,
    this.totalLayers,
    this.bedTemp,
    this.bedTarget,
    this.nozzleTemp,
    this.nozzleTarget,
    this.chamberTemp,
    this.nozzleType,
    this.nozzleDiameter,
    this.speedLevel,
    this.speedMag,
    this.subtaskName,
    this.taskId,
    this.jobId,
    this.wifiSignal,
  });
}

// =============================
// High-Level Orchestrating Class
// =============================

class BambuLan {
  final BambuLanConfig config;
  late final BambuMqtt mqtt = BambuMqtt(config);
  //late final BambuFtp ftp = BambuFtp(config);

  Stream<BambuReportEvent> get reportStream => mqtt.reportStream;

  BambuLan({required this.config});

  Future<void> connect() async {
    await mqtt.connect();
  }

  Future<void> dispose() async {
    await mqtt.dispose();
    //await ftp.dispose();
  }
}

// // =========
// // FTP Client
// // =========

// class BambuFtp {
//   final BambuLanConfig config;
//   FTPConnect? _ftp; // lazily connected

//   BambuFtp(this.config);

//   Future<FTPConnect> _get() async {
//     if (_ftp != null) return _ftp!;

//     SecurityType securityType = SecurityType.FTP;
//     if (config.useFtps) {
//       // Try explicit TLS (FTPES). If server rejects, most libs gracefully fall back.
//       securityType = SecurityType.FTPES;
//     }

//     final ftp = FTPConnect(
//       config.printerIp,
//       user: 'bblp',
//       pass: config.accessCode,
//       port: config.ftpPort,
//       securityType: securityType,
//       timeout: const Duration(seconds: 15).inSeconds,
//     );
//     await ftp.connect();
//     _ftp = ftp;
//     return ftp;
//   }

//   Future<void> dispose() async {
//     try {
//       await _ftp?.disconnect();
//     } catch (_) {}
//     _ftp = null;
//   }

//   Future<List<FtpEntry>> list(String path) async {
//     final ftp = await _get();
//     //path: path
//     final raw = await ftp.listDirectoryContent();
//     return raw.map((e) {
//       return FtpEntry(
//         name: e.name ?? '',
//         //isDir: e.,
//         isDir: true,
//         size: e.size,
//         modified: e.modifyTime,
//         path: e.modifyTime != null ? '$path/${e.name}' : '$path/${e.name}',
//       );
//     }).toList();
//   }

//   Future<void> ensureDir(String path) async {
//     final ftp = await _get();
//     await ftp.createFolderIfNotExist(path);
//   }

//   /// Upload a local file (by path) to a remote full path (including filename).
//   Future<void> upload({
//     required String localPath,
//     required String remotePath,
//   }) async {
//     final ftp = await _get();
//     final file = File(localPath);
//     if (!await file.exists()) {
//       throw ArgumentError('Local file does not exist: $localPath');
//     }
//     final remoteDir = remotePath.substring(0, remotePath.lastIndexOf('/'));
//     await ftp.createFolderIfNotExist(remoteDir);
//     await ftp.changeDirectory(remoteDir);
//     //await ftp.uploadFile(file, sRetryCount: 2);
//   }
// }
