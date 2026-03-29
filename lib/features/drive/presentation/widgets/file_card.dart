import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    return GestureDetector(
      onLongPress: () => _showOptions(context, ref),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail area
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: _typeColor(fileType).withOpacity(0.1),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Stack(
                  children: [
                    Center(child: Icon(_typeIcon(fileType), color: _typeColor(fileType), size: 48)),
                    if (file.isStarred)
                      const Positioned(
                        top: 8, right: 8,
                        child: Icon(Icons.star_rounded, color: AppTheme.warning, size: 18),
                      ),
                  ],
                ),
              ),
            ),
            // Info area
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
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                ],
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
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(_typeIcon(ZXFileTypeX.fromMime(file.mimeType)),
                      color: _typeColor(ZXFileTypeX.fromMime(file.mimeType)), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(file.name,
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
            ListTile(
              leading: const Icon(Icons.download_rounded, color: AppTheme.primary),
              title: const Text('Download', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await repo.downloadFile(file: file);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Downloaded successfully!')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Download failed: $e')),
                  );
                }
              },
            ),
            ListTile(
              leading: Icon(
                file.isStarred ? Icons.star_border_rounded : Icons.star_rounded,
                color: AppTheme.warning,
              ),
              title: Text(
                file.isStarred ? 'Unstar' : 'Star',
                style: const TextStyle(color: AppTheme.textPrimary),
              ),
              onTap: () {
                repo.toggleStar(file);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: AppTheme.accent),
              title: const Text('Rename', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(context, repo);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: AppTheme.error),
              title: const Text('Delete', style: TextStyle(color: AppTheme.error)),
              onTap: () {
                repo.deleteFile(file);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, FileRepository repo) {
    final controller = TextEditingController(text: file.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Rename File',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'File name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                repo.renameFile(file, controller.text.trim());
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
      case ZXFileType.image: return Icons.image_rounded;
      case ZXFileType.video: return Icons.play_circle_rounded;
      case ZXFileType.audio: return Icons.music_note_rounded;
      case ZXFileType.document: return Icons.description_rounded;
      case ZXFileType.archive: return Icons.folder_zip_rounded;
      case ZXFileType.other: return Icons.insert_drive_file_rounded;
    }
  }

  Color _typeColor(ZXFileType type) {
    switch (type) {
      case ZXFileType.image: return const Color(0xFF00C48C);
      case ZXFileType.video: return const Color(0xFF4F6FFF);
      case ZXFileType.audio: return const Color(0xFFFFB800);
      case ZXFileType.document: return const Color(0xFFDB2777);
      case ZXFileType.archive: return const Color(0xFF7C3AED);
      case ZXFileType.other: return AppTheme.textSecondary;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }
}
