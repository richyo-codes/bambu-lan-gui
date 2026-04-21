import 'package:boomprint/bambu_lan.dart';
import 'package:boomprint/connection_preflight.dart';
import 'package:boomprint/printer_firmware.dart';
import 'package:boomprint/settings_manager.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

String? formatNozzleInfo(BambuPrintStatus? ps) {
  if (ps == null) return null;
  final type = ps.nozzleType?.trim() ?? '';
  final diameter = ps.nozzleDiameter?.trim() ?? '';
  if (type.isEmpty && diameter.isEmpty) return null;
  if (type.isNotEmpty && diameter.isNotEmpty) return '$type • $diameter';
  return type.isNotEmpty ? type : diameter;
}

String? formatJobIds(BambuPrintStatus? ps) {
  if (ps == null) return null;
  final job = ps.jobId?.trim() ?? '';
  final task = ps.taskId?.trim() ?? '';
  if (job.isEmpty && task.isEmpty) return null;
  if (job.isNotEmpty && task.isNotEmpty) {
    return 'Job ID: $job • Task ID: $task';
  }
  return job.isNotEmpty ? 'Job ID: $job' : 'Task ID: $task';
}

String? formatPrintFileTitle(BambuPrintStatus? ps) {
  if (ps == null) return null;
  final subtask = ps.subtaskName?.trim();
  if (subtask != null && subtask.isNotEmpty) {
    return subtask;
  }
  final gcodeFile = ps.gcodeFile?.trim();
  if (gcodeFile == null || gcodeFile.isEmpty) {
    return null;
  }
  return path.basename(gcodeFile);
}

String? buildTitleSummary(BambuPrintStatus? ps) {
  final lines = <String>[];
  final printFile = formatPrintFileTitle(ps);
  if (printFile != null) {
    lines.add('Print: $printFile');
  }
  final nozzleInfo = formatNozzleInfo(ps);
  if (nozzleInfo != null) {
    lines.add('Nozzle: $nozzleInfo');
  }
  final ids = formatJobIds(ps);
  if (ids != null) {
    lines.add(ids);
  }
  if (lines.isEmpty) return null;
  return lines.join(' • ');
}

class MetricsPanel extends StatelessWidget {
  final BambuPrintStatus ps;
  const MetricsPanel({super.key, required this.ps});

  @override
  Widget build(BuildContext context) {
    String fmtTemp(double? t) => t == null ? '-' : '${t.toStringAsFixed(0)}°C';
    String fmtRssi(String? s) => s == null || s.isEmpty ? '-' : s;
    String fmtLayer(int? l, int? t) =>
        (l == null && t == null) ? '-' : '${l ?? '?'} / ${t ?? '?'}';
    String fmtSpeed(int? level, int? mag) {
      if (level == null && mag == null) return '-';
      if (level != null && mag != null) return 'L$level ($mag%)';
      if (level != null) return 'L$level';
      return '$mag%';
    }

    final styleValue = Theme.of(context).textTheme.bodySmall;

    Widget item(IconData icon, String value) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Text(value, style: styleValue),
      ],
    );

    final items = <Widget>[
      if (ps.nozzleTemp != null || ps.nozzleTarget != null)
        item(
          Icons.local_fire_department,
          '${fmtTemp(ps.nozzleTemp)} / ${fmtTemp(ps.nozzleTarget)}',
        ),
      if (ps.bedTemp != null || ps.bedTarget != null)
        item(
          Icons.grid_on,
          '${fmtTemp(ps.bedTemp)} / ${fmtTemp(ps.bedTarget)}',
        ),
      if (ps.chamberTemp != null)
        item(Icons.crop_square, fmtTemp(ps.chamberTemp)),
      if (ps.speedLevel != null || ps.speedMag != null)
        item(Icons.speed, fmtSpeed(ps.speedLevel, ps.speedMag)),
      if (ps.wifiSignal != null && ps.wifiSignal!.isNotEmpty)
        item(Icons.wifi, fmtRssi(ps.wifiSignal)),
      if (ps.layer != null || ps.totalLayers != null)
        item(Icons.layers, fmtLayer(ps.layer, ps.totalLayers)),
      if (ps.percent != null) item(Icons.percent, '${ps.percent}%'),
      if (ps.remainingMinutes != null)
        item(Icons.timelapse, '${ps.remainingMinutes}m'),
    ];

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Wrap(spacing: 12, runSpacing: 6, children: items),
      ),
    );
  }
}

class PrintOverlayStatus extends StatelessWidget {
  final BambuPrintStatus? status;
  const PrintOverlayStatus({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            'Waiting for MQTT status…',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      );
    }

    final parts = <String>[];
    if (status!.gcodeState.isNotEmpty) {
      parts.add(status!.gcodeState);
    }
    if (status!.percent != null) {
      parts.add('${status!.percent}%');
    }
    if (status!.remainingMinutes != null) {
      parts.add('${status!.remainingMinutes}m left');
    }
    if (status!.layer != null || status!.totalLayers != null) {
      final layer = status!.layer?.toString() ?? '?';
      final total = status!.totalLayers?.toString() ?? '?';
      parts.add('Layer $layer / $total');
    }
    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          parts.join(' • '),
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }
}

class FirmwareWarningBanner extends StatelessWidget {
  final PrinterFirmwareWarning warning;
  final VoidCallback? onOpenHelp;

  const FirmwareWarningBanner({
    super.key,
    required this.warning,
    this.onOpenHelp,
  });

  @override
  Widget build(BuildContext context) {
    final helpUrl = warning.helpEntry.links.isNotEmpty
        ? warning.helpEntry.links.first.url
        : null;
    return MaterialBanner(
      backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
      leading: Icon(
        Icons.warning_amber_rounded,
        color: Theme.of(context).colorScheme.onTertiaryContainer,
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Firmware may be too old',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            warning.message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onTertiaryContainer,
            ),
          ),
          if (warning.firmwareVersion.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Detected firmware: ${warning.firmwareVersion}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onTertiaryContainer,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (helpUrl != null)
          TextButton(
            onPressed: onOpenHelp,
            child: const Text('Firmware updates'),
          ),
      ],
    );
  }
}

class DisconnectedBody extends StatelessWidget {
  final VoidCallback onOpenSettings;
  final Future<void> Function(String url) onConnect;

  const DisconnectedBody({
    super.key,
    required this.onOpenSettings,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'No active stream',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onOpenSettings,
            child: const Text('Configure Stream'),
          ),
          ElevatedButton(
            onPressed: () async {
              final settings = SettingsManager.settings;
              final streamUrl = ConnectionPreflight.buildStreamUrl(settings);
              if (streamUrl.trim().isEmpty) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please configure printer settings first'),
                    ),
                  );
                }
                return;
              }

              final summary = await ConnectionPreflight.run(
                settings: settings,
                streamUrl: streamUrl,
              );
              if (!context.mounted) return;

              if (summary.hasRequiredFailures) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(summary.summaryLine)));
                return;
              }

              final optionalFailures = summary.optionalFailures.toList();
              if (optionalFailures.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Printer stream is reachable. ${optionalFailures.map((r) => r.label).join(', ')} unavailable, but optional.',
                    ),
                  ),
                );
              }

              await onConnect(streamUrl);
            },
            child: const Text('Connect to Printer'),
          ),
        ],
      ),
    );
  }
}
