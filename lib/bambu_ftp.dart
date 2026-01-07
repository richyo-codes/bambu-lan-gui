// // =========
// // FTP Client
// // =========

import 'dart:async';
import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:intl/intl.dart';
import 'package:meta/meta.dart';
import 'package:rnd_bambu_rtsp_stream/bambu_lan.dart';

class BambuFtp {
  final BambuLanConfig config;
  FTPConnect? _ftp; // lazily connected

  BambuFtp(this.config, {FTPConnect? client}) {
    _ftp = client;
  }

  Future<FTPConnect> _get() async {
    if (_ftp != null) return _ftp!;

    // Use FTPS by default (implicit TLS on 990 per OpenBambu docs).
    final useFtps = config.useFtps;
    SecurityType securityType = useFtps ? SecurityType.ftps : SecurityType.ftp;

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
    ftp.listCommand = ListCommand.list;
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
    final target = path.isEmpty ? '/' : path;
    try {
      final resp = await ftp
          .sendCustomCommand('ls $target')
          .timeout(
            timeout,
            onTimeout: () {
              throw TimeoutException('FTP ls timed out', timeout);
            },
          );
      final entries = parseLsResponse(resp.message, currentPath: target);
      if (entries.isEmpty) {
        throw FTPConnectException('FTP ls returned no data');
      }
      return entries;
    } on TimeoutException {
      await dispose();
      throw TimeoutException(
        'FTP list timed out after ${timeout.inSeconds}s',
        timeout,
      );
    }
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

  @visibleForTesting
  static List<FtpEntry> parseLsResponse(
    String message, {
    String currentPath = '/',
  }) {
    final entries = <FtpEntry>[];
    for (final rawLine in message.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (RegExp(r'^\d{3}').hasMatch(line)) continue; // skip reply codes
      final parsed = _parseUnixListLine(line, currentPath);
      if (parsed != null) entries.add(parsed);
    }
    return entries;
  }

  static FtpEntry? _parseUnixListLine(String line, String currentPath) {
    final re = RegExp(
      r'^([\-ld])([rwx\-]{9})\s+\d+\s+\S+\s+\S+\s+(\d+)\s+'
      r'([A-Za-z]{3}\s+\d{1,2}\s+(?:\d{2}:\d{2}|\d{4}))\s+(.+)$',
    );
    final m = re.firstMatch(line);
    if (m == null) return null;
    final typeChar = m.group(1);
    final size = int.tryParse(m.group(3) ?? '');
    final dateStr = m.group(4)!;
    final name = m.group(5) ?? '';

    DateTime? modified;
    try {
      final now = DateTime.now();
      final withYear = dateStr.contains(':') ? '$dateStr ${now.year}' : dateStr;
      final fmt = dateStr.contains(':') ? 'MMM d HH:mm yyyy' : 'MMM d yyyy';
      modified = DateFormat(fmt, 'en_US').parse(withYear);
    } catch (_) {}

    String buildPath(String base, String name) {
      if (base.isEmpty || base == '/') return '/$name';
      return base.endsWith('/') ? '$base$name' : '$base/$name';
    }

    return FtpEntry(
      name: name,
      isDir: typeChar == 'd',
      path: buildPath(currentPath, name),
      size: size,
      modified: modified,
    );
  }
}
