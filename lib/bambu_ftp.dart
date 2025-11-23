// // =========
// // FTP Client
// // =========

import 'dart:async';
import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_lan.dart';

class BambuFtp {
  final BambuLanConfig config;
  FTPConnect? _ftp; // lazily connected
  bool _plainOverride = false; // fall back if FTPS data channel hangs
  bool _forceProtClear =
      false; // allow clear data channel while keeping TLS control

  BambuFtp(this.config);

  Future<FTPConnect> _get() async {
    if (_ftp != null) return _ftp!;

    final useFtps = config.useFtps && !_plainOverride;
    SecurityType securityType = useFtps ? SecurityType.ftps : SecurityType.ftp;
    // Try explicit TLS (FTPES) when FTPS requested; if server rejects, most libs gracefully fall back.
    //securityType = SecurityType.ftpes;

    var logger = Logger(isEnabled: true);

    final ftp = FTPConnect(
      config.printerIp,
      user: 'bblp',
      pass: config.accessCode,
      port: useFtps ? config.ftpPort : 21,
      securityType: securityType,
      showLog: false,
      logger: logger,
      timeout: const Duration(seconds: 15).inSeconds,
    );
    // Prefer classic LIST for compatibility (vsftpd often lacks MLSD)
    ftp.listCommand = ListCommand.nlst;
    await ftp.connect().timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        throw TimeoutException(
          'FTP connect timeout (12s)',
          const Duration(seconds: 12),
        );
      },
    );
    _ftp = ftp;
    if (useFtps && _forceProtClear) {
      // Allow clear data channel if TLS data sockets hang
      await ftp.sendCustomCommand('PROT C');
    }
    return ftp;
  }

  Future<void> dispose() async {
    try {
      await _ftp?.disconnect();
    } catch (_) {}
    _ftp = null;
  }

  Future<List<FtpEntry>> list(
    String path, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final ftp = await _get();
    if (path.isNotEmpty) {
      final ok = await ftp.changeDirectory(path);
      if (!ok) {
        throw FTPConnectException('Failed to change directory to $path');
      }
    }
    List<FTPEntry> raw;
    try {
      raw = await ftp.listDirectoryContent().timeout(timeout);
    } on TimeoutException {
      // Reset connection so the next attempt starts fresh
      await dispose();
      if (config.useFtps && !_forceProtClear) {
        // FTPS data sockets sometimes hang; try clear data while keeping TLS control.
        _forceProtClear = true;
        return list(path, timeout: timeout);
      }
      if (config.useFtps && !_plainOverride) {
        // If clear-data FTPS still fails, drop to plain FTP as a last resort.
        _plainOverride = true;
        return list(path, timeout: timeout);
      }
      throw TimeoutException(
        'FTP list timed out after ${timeout.inSeconds}s',
        timeout,
      );
    }
    return raw.map((e) {
      final name = e.name;
      final isDir = e.type == FTPEntryType.dir;
      final size = e.size;
      final modified = e.modifyTime;
      // Normalize path composition; avoid double slashes
      String buildPath(String base, String name) {
        if (base.isEmpty || base == '/') return '/$name';
        return base.endsWith('/') ? '$base$name' : '$base/$name';
      }

      return FtpEntry(
        name: name,
        isDir: isDir,
        size: size,
        modified: modified,
        path: buildPath(path, name),
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
    await ftp.uploadFileWithRetry(file, pRetryCount: 2);
  }
}
