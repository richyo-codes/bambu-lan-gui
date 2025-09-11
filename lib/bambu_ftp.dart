// // =========
// // FTP Client
// // =========

import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_lan.dart';

class BambuFtp {
  final BambuLanConfig config;
  FTPConnect? _ftp; // lazily connected

  BambuFtp(this.config);

  Future<FTPConnect> _get() async {
    if (_ftp != null) return _ftp!;

    SecurityType securityType = SecurityType.ftp;
    if (config.useFtps) {
      // Try explicit TLS (FTPES). If server rejects, most libs gracefully fall back.
      securityType = SecurityType.ftpes;
    }

    final ftp = FTPConnect(
      config.printerIp,
      user: 'bblp',
      pass: config.accessCode,
      port: config.ftpPort,
      securityType: securityType,
      timeout: const Duration(seconds: 15).inSeconds,
    );
    await ftp.connect();
    _ftp = ftp;
    return ftp;
  }

  Future<void> dispose() async {
    try {
      await _ftp?.disconnect();
    } catch (_) {}
    _ftp = null;
  }

  Future<List<FtpEntry>> list(String path) async {
    final ftp = await _get();
    //path: path
    final raw = await ftp.listDirectoryContent();
    return raw.map((e) {
      return FtpEntry(
        name: e.name ?? '',
        //isDir: e.,
        isDir: true,
        size: e.size,
        modified: e.modifyTime,
        path: e.modifyTime != null ? '$path/${e.name}' : '$path/${e.name}',
      );
    }).toList();
  }

  Future<void> ensureDir(String path) async {
    final ftp = await _get();
    await ftp.createFolderIfNotExist(path);
  }

  /// Upload a local file (by path) to a remote full path (including filename).
  Future<void> upload({
    required String localPath,
    required String remotePath,
  }) async {
    final ftp = await _get();
    final file = File(localPath);
    if (!await file.exists()) {
      throw ArgumentError('Local file does not exist: $localPath');
    }
    final remoteDir = remotePath.substring(0, remotePath.lastIndexOf('/'));
    await ftp.createFolderIfNotExist(remoteDir);
    await ftp.changeDirectory(remoteDir);
    //await ftp.uploadFile(file, sRetryCount: 2);
  }
}
