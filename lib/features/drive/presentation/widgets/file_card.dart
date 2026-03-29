import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/file_repository.dart';
import '../../domain/models/zx_file.dart';
import '../providers/drive_providers.dart';

class FileCard extends ConsumerWidget {
  final FileItem file;
  const FileCard({super.key, required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileType = ZXFileTypeX.fromMime(file.mimeType);
    final selectedUuids = ref.watch(selectionProvider);
    final isSelectionMode = selectedUuids.isNotEmpty;
    final isSelected = selectedUuids.contains(file.uuid);

    return GestureDetector(
      onTap: () {
        if (isSelectionMode) {
          ref.read(selectionProvider.notifier).toggle(file.uuid);
        }
      },
      onLongPress: () {
        if (!isSelectionMode) {
          ref.read(selectionProvider.notifier).toggle(file.uuid);
        } else {
          _showOptions(context, ref);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withOpacity(0.15)
              : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.primary
                : Colors.white.withOpacity(0.05),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _typeColor(fileType).withOpacity(0.1),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16)),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Icon(_typeIcon(fileType),
                              color: _typeColor(fileType), size: 48),
                        ),
                        if (file.isStarred)
                          const Positioned(
                            top: 8,
                            right: 8,
                            child: Icon(Icons.star_rounded,
                                color: AppTheme.warning, size: 18),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatSize(file.sizeBytes),
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isSelectionMode)
              Positioned(
                top: 8,
                left: 8,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color:
                        isSelected ? AppTheme.primary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 14)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    final repo = ref.read(fileRepositoryProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // Use a builder so the sheet gets its own subtree for ScaffoldMessenger
      builder: (sheetCtx) => _FileOptionsSheet(
        file: file,
        repo: repo,
      ),
    );
  }

  IconData _typeIcon(ZXFileType type) {
    switch (type) {
      case ZXFileType.image:
        return Icons.image_rounded;
      case ZXFileType.video:
        return Icons.play_circle_rounded;
      case ZXFileType.audio:
        return Icons.music_note_rounded;
      case ZXFileType.document:
        return Icons.description_rounded;
      case ZXFileType.archive:
        return Icons.folder_zip_rounded;
      case ZXFileType.other:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _typeColor(ZXFileType type) {
    switch (type) {
      case ZXFileType.image:
        return const Color(0xFF00C48C);
      case ZXFileType.video:
        return const Color(0xFF4F6FFF);
      case ZXFileType.audio:
        return const Color(0xFFFFB800);
      case ZXFileType.document:
        return const Color(0xFFDB2777);
      case ZXFileType.archive:
        return const Color(0xFF7C3AED);
      case ZXFileType.other:
        return AppTheme.textSecondary;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }
}

// ── File Options Sheet ────────────────────────────────────
// Extracted as its own StatefulWidget so it can:
//   1. Watch a live stream of the file to always have fresh isStarred state
//   2. Use its own BuildContext that stays valid after Navigator.pop()

class _FileOptionsSheet extends ConsumerStatefulWidget {
  final FileItem file;
  final FileRepository repo;

  const _FileOptionsSheet({required this.file, required this.repo});

  @override
  ConsumerState<_FileOptionsSheet> createState() => _FileOptionsSheetState();
}

class _FileOptionsSheetState extends ConsumerState<_FileOptionsSheet> {
  bool _downloading = false;

  // Keep a live copy of the file so star state is always fresh
  late FileItem _file;

  @override
  void initState() {
    super.initState();
    _file = widget.file;
  }

  @override
  Widget build(BuildContext context) {
    // Watch the files stream so isStarred updates live inside the sheet
    final filesAsync = ref.watch(filesProvider(widget.file.folderId));
    filesAsync.whenData((files) {
      final updated =
          files.where((f) => f.uuid == widget.file.uuid).firstOrNull;
      if (updated != null && updated.isStarred != _file.isStarred) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _file = updated);
        });
      }
    });

    final fileType = ZXFileTypeX.fromMime(_file.mimeType);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textSecondary.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          // File header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(_typeIcon(fileType), color: _typeColor(fileType), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_file.name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          const Divider(color: AppTheme.bgSurface),
          // Download
          ListTile(
            leading: _downloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary),
                  )
                : const Icon(Icons.download_rounded, color: AppTheme.primary),
            title: Text(
              _downloading ? 'Downloading...' : 'Download',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            subtitle: _file.sizeBytes > 20 * 1024 * 1024
                ? const Text('File > 20 MB — Bot API limit',
                    style: TextStyle(color: AppTheme.warning, fontSize: 11))
                : null,
            onTap: _downloading ? null : _downloadFile,
          ),
          // Star / Unstar — always reads from fresh _file
          ListTile(
            leading: Icon(
              _file.isStarred
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              color: AppTheme.warning,
            ),
            title: Text(
              _file.isStarred ? 'Unstar' : 'Star',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            onTap: () async {
              await widget.repo.toggleStar(_file);
              // Close sheet — the grid will rebuild with fresh data from the stream
              if (mounted) Navigator.pop(context);
            },
          ),
          // Rename
          ListTile(
            leading: const Icon(Icons.edit_rounded, color: AppTheme.accent),
            title: const Text('Rename',
                style: TextStyle(color: AppTheme.textPrimary)),
            onTap: () {
              Navigator.pop(context);
              _showRenameDialog();
            },
          ),
          // Delete (soft — goes to trash)
          ListTile(
            leading: const Icon(Icons.delete_rounded, color: AppTheme.error),
            title: const Text('Move to Trash',
                style: TextStyle(color: AppTheme.error)),
            onTap: () {
              widget.repo.deleteFile(_file);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _downloadFile() async {
    setState(() => _downloading = true);
    // Capture scaffold messenger BEFORE any async gap
    final messenger = ScaffoldMessenger.of(context);

    try {
      final savePath = await widget.repo.downloadFile(file: _file);

      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved: ${savePath.split('/').last}'),
          action: SnackBarAction(
            label: 'OPEN',
            onPressed: () => OpenFile.open(savePath),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _showRenameDialog() {
    final controller = TextEditingController(text: _file.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Rename File',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'File name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                widget.repo.renameFile(_file, controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  IconData _typeIcon(ZXFileType type) {
    switch (type) {
      case ZXFileType.image:
        return Icons.image_rounded;
      case ZXFileType.video:
        return Icons.play_circle_rounded;
      case ZXFileType.audio:
        return Icons.music_note_rounded;
      case ZXFileType.document:
        return Icons.description_rounded;
      case ZXFileType.archive:
        return Icons.folder_zip_rounded;
      case ZXFileType.other:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _typeColor(ZXFileType type) {
    switch (type) {
      case ZXFileType.image:
        return const Color(0xFF00C48C);
      case ZXFileType.video:
        return const Color(0xFF4F6FFF);
      case ZXFileType.audio:
        return const Color(0xFFFFB800);
      case ZXFileType.document:
        return const Color(0xFFDB2777);
      case ZXFileType.archive:
        return const Color(0xFF7C3AED);
      case ZXFileType.other:
        return AppTheme.textSecondary;
    }
  }
}
