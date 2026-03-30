import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/file_repository.dart';
import '../../domain/models/zx_file.dart';
import '../providers/drive_providers.dart';

class TrashPage extends ConsumerWidget {
  const TrashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(trashProvider);
    return filesAsync.when(
      data: (files) {
        if (files.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_outline_rounded,
                    color: AppTheme.textSecondary, size: 56),
                SizedBox(height: 16),
                Text('Trash is empty',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                Text('Deleted files will appear here',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ],
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${files.length} item(s)',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                  TextButton.icon(
                    onPressed: () => _confirmEmptyTrash(context, ref, files),
                    icon: const Icon(Icons.delete_forever_rounded,
                        color: AppTheme.error, size: 16),
                    label: const Text('Empty Trash',
                        style: TextStyle(color: AppTheme.error, fontSize: 13)),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppTheme.textSecondary, size: 13),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Files here are still stored on Telegram. '
                      'Restore to bring them back, or delete permanently.',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: files.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _TrashFileCard(file: files[i]),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primary)),
      error: (e, _) => const SizedBox.shrink(),
    );
  }

  Future<void> _confirmEmptyTrash(
      BuildContext context, WidgetRef ref, List<FileItem> files) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Empty Trash',
            style: TextStyle(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          'Permanently delete ${files.length} file(s) from Telegram? '
          'This cannot be undone.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final repo = ref.read(fileRepositoryProvider);
    final uuids = files.map((f) => f.uuid).toList();
    await repo.bulkPermanentDelete(uuids);
  }
}

// ── Individual trash card with restore + delete actions ──

class _TrashFileCard extends ConsumerWidget {
  final FileItem file;
  const _TrashFileCard({required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileType = ZXFileTypeX.fromMime(file.mimeType);
    final repo = ref.read(fileRepositoryProvider);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _typeColor(fileType).withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_typeIcon(fileType),
              color: _typeColor(fileType), size: 22),
        ),
        title: Text(
          file.name,
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _formatSize(file.sizeBytes),
          style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Restore button
            _ActionChip(
              icon: Icons.restore_rounded,
              label: 'Restore',
              color: AppTheme.primary,
              onTap: () async {
                await repo.restoreFile(file);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${file.name} restored'),
                      backgroundColor: AppTheme.primary,
                    ),
                  );
                }
              },
            ),
            const SizedBox(width: 8),
            // Permanent delete button
            _ActionChip(
              icon: Icons.delete_forever_rounded,
              label: 'Delete',
              color: AppTheme.error,
              onTap: () => _confirmDelete(context, repo),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, FileRepository repo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Permanently',
            style: TextStyle(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          'Delete "${file.name}" from Telegram forever?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );

    if (confirmed == true) await repo.permanentlyDelete(file);
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
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
