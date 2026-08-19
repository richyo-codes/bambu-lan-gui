import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'window_drag_controller.dart';
import 'app_strings.dart';
import 'screenshot_storage.dart';

/// A gallery screen that lists all screenshots captured from the video stream.
class ScreenshotGalleryPage extends StatefulWidget {
  const ScreenshotGalleryPage({super.key});

  @override
  State<ScreenshotGalleryPage> createState() => _ScreenshotGalleryPageState();
}

class _ScreenshotGalleryPageState extends State<ScreenshotGalleryPage> {
  List<_ScreenshotFile> _files = const [];
  bool _loading = true;
  String? _error;
  String? _selectedPath;

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dirs = await ScreenshotStorage.galleryDirectories();
      final files = <_ScreenshotFile>[];
      for (final dir in dirs) {
        if (!await dir.exists()) {
          continue;
        }

        final entities = await dir.list().toList();
        for (final entity in entities) {
          final basename = path.basename(entity.path).toLowerCase();
          if (!basename.endsWith('.png') &&
              !basename.endsWith('.jpg') &&
              !basename.endsWith('.jpeg')) {
            continue;
          }
          final stat = await entity.stat();
          files.add(
            _ScreenshotFile(
              path: entity.path,
              size: stat.size,
              modified: stat.modified,
            ),
          );
        }
      }

      if (files.isEmpty) {
        setState(() {
          _files = const [];
          _loading = false;
        });
        return;
      }

      files.sort((a, b) => b.modified.compareTo(a.modified));

      if (!mounted) return;
      setState(() {
        _files = files;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<void> _confirmAndDelete(String filePath) async {
    final filename = path.basename(filePath);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete screenshot'),
        content: Text('Delete "$filename"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _deleteFile(filePath);
    _loadFiles();
  }

  Future<void> _showFullImage(String filePath) async {
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.92),
        pageBuilder: (context, _, _) => _FullImageViewer(path: filePath),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    return FramelessWindowResizeFrame(
      child: Scaffold(
        appBar: WindowChromeHeader(
          title: const Text(AppStrings.appDisplayName),
          subtitle: const Text('Screenshots'),
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          actions: [
            IconButton(onPressed: _loadFiles, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadFiles, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            const Text(
              'No screenshots yet',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            const Text(
              'Capture screenshots from the video stream to see them here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Text(
            '${_files.length} screenshot${_files.length == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 280,
              childAspectRatio: 16 / 10,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: _files.length,
            itemBuilder: (context, index) {
              final file = _files[index];
              final isSel = _selectedPath == file.path;
              return _buildThumbnail(file, isSel);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnail(_ScreenshotFile file, bool isSelected) {
    return MouseRegion(
      onEnter: (_) {
        if (mounted) {
          setState(() => _selectedPath = file.path);
        }
      },
      onExit: (_) {
        if (isSelected && mounted) {
          setState(() => _selectedPath = null);
        }
      },
      child: GestureDetector(
        onTap: () => _showFullImage(file.path),
        onLongPress: () => _confirmAndDelete(file.path),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            border: isSelected
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : Border.all(color: Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(File(file.path), fit: BoxFit.cover),
                // Fade out timestamp overlay for visibility
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatTimestamp(file.modified),
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                ),
                // Delete button on hover
                Positioned(
                  right: 4,
                  top: 4,
                  child: Visibility(
                    visible: isSelected,
                    child: Material(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      child: IconButton(
                        icon: const Icon(
                          Icons.delete,
                          size: 16,
                          color: Colors.white,
                        ),
                        onPressed: () => _confirmAndDelete(file.path),
                        iconSize: 16,
                        padding: const EdgeInsets.all(4),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final mo = (dt.month).toString().padLeft(2, '0');
    final y = dt.year;
    return '$y-$mo-$d $h:$m';
  }
}

/// Full-screen image viewer shown as a modal page route.
class _FullImageViewer extends StatelessWidget {
  final String path;

  const _FullImageViewer({required this.path});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: InteractiveViewer(
            child: Image.file(File(path), fit: BoxFit.contain),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.of(context).pop(),
          backgroundColor: Colors.black54,
          child: const Icon(Icons.close),
        ),
      ),
    );
  }
}

/// Lightweight model for a screenshot file on disk.
class _ScreenshotFile {
  final String path;
  final int size;
  final DateTime modified;

  const _ScreenshotFile({
    required this.path,
    required this.size,
    required this.modified,
  });
}
