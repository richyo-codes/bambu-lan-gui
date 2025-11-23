// // =========
// // FTP Client
// // =========

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:intl/intl.dart';
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
    if (useFtps && _forceProtClear) {
      // Allow clear data channel if TLS data sockets hang
      //await ftp.sendCustomCommand('PROT C');
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
    // Some servers expose an inline "ls" that returns data on the control
    // socket; try that first to avoid hanging data channels.
    final lsEntries = await _tryCustomLs(ftp, path, timeout);
    if (lsEntries != null && lsEntries.isNotEmpty) return lsEntries;

    final manual = await _manualListPath(path, timeout);
    if (manual != null && manual.isNotEmpty) return manual;

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

  Future<List<FtpEntry>?> _tryCustomLs(
    FTPConnect ftp,
    String currentPath,
    Duration timeout,
  ) async {
    try {
      final resp = await ftp
          .sendCustomCommand('ls')
          .timeout(
            timeout,
            onTimeout: () {
              throw TimeoutException('FTP ls timed out', timeout);
            },
          );
      final entries = <FtpEntry>[];
      for (final rawLine in resp.message.split('\n')) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        if (RegExp(r'^\d{3}').hasMatch(line)) continue; // skip reply lines
        final parsed = _parseUnixListLine(line, currentPath);
        if (parsed != null) entries.add(parsed);
      }
      return entries.isEmpty ? null : entries;
    } catch (_) {
      return null;
    }
  }

  FtpEntry? _parseUnixListLine(String line, String currentPath) {
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

  Future<List<FtpEntry>?> _manualListPath(
    String path,
    Duration timeout,
  ) async {
    final host = config.printerIp;
    final port = config.useFtps ? config.ftpPort : 21;
    final useTls = config.useFtps && !_forceProtClear && !_plainOverride;
    final cmdPath = path.isEmpty ? '/' : path;

    Socket control;
    if (useTls) {
      control = await SecureSocket.connect(
        host,
        port,
        onBadCertificate: (_) => config.allowBadCerts,
        timeout: timeout,
      );
    } else {
      control = await Socket.connect(host, port, timeout: timeout);
    }
    final controlStream = control.asBroadcastStream();

    Future<_FtpReply> readReply() async {
      final lines = <String>[];
      int? code;
      final completer = Completer<_FtpReply>();
      late StreamSubscription<String> sub;
      sub = controlStream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        lines.add(line);
        if (line.length >= 3 && int.tryParse(line.substring(0, 3)) != null) {
          code ??= int.parse(line.substring(0, 3));
          final isFinal =
              line.length >= 4 && line.startsWith('$code') && line[3] == ' ';
          if (isFinal) {
            completer.complete(_FtpReply(code!, lines.join('\n')));
            sub.cancel();
          }
        }
      });
      return completer.future.timeout(timeout, onTimeout: () {
        sub.cancel();
        throw TimeoutException('FTP control timed out', timeout);
      });
    }

    Future<_FtpReply> send(String cmd) {
      control.write('$cmd\r\n');
      return readReply();
    }

    try {
      await readReply(); // welcome
      var r = await send('USER bblp');
      if (r.code == 331) {
        r = await send('PASS ${config.accessCode}');
      }
      if (useTls && !_forceProtClear) {
        await send('PBSZ 0');
        await send('PROT P');
      } else if (useTls && _forceProtClear) {
        await send('PBSZ 0');
        await send('PROT C');
      }

      final pasv = await send('PASV');
      final portMatch = RegExp(r'\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)')
          .firstMatch(pasv.message);
      if (portMatch == null) return null;
      final dataPort = (int.parse(portMatch.group(5)!) << 8) +
          int.parse(portMatch.group(6)!);

      final dataSocket = useTls && !_forceProtClear
          ? await SecureSocket.connect(
              host,
              dataPort,
              onBadCertificate: (_) => config.allowBadCerts,
              timeout: timeout,
            )
          : await Socket.connect(host, dataPort, timeout: timeout);

      final dataLines = StringBuffer();
      final dataDone = Completer<void>();
      dataSocket
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(dataLines.writeln, onDone: () {
        dataDone.complete();
      });

      await send('LIST $cmdPath');
      await dataDone.future.timeout(timeout, onTimeout: () {
        dataSocket.destroy();
        throw TimeoutException('FTP data timed out', timeout);
      });
      dataSocket.destroy();
      await readReply(); // transfer complete

      final entries = <FtpEntry>[];
      for (final raw in dataLines.toString().split('\n')) {
        final t = raw.trim();
        if (t.isEmpty) continue;
        final parsed = _parseUnixListLine(t, path);
        if (parsed != null) entries.add(parsed);
      }
      return entries;
    } catch (_) {
      return null;
    } finally {
      try {
        control.write('QUIT\r\n');
      } catch (_) {}
      control.destroy();
    }
  }
}

class _FtpReply {
  final int code;
  final String message;
  _FtpReply(this.code, this.message);
}
