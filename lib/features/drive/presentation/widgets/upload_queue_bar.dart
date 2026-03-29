import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/zx_file.dart';
import '../providers/drive_providers.dart';

class UploadQueueBar extends ConsumerWidget {
  const UploadQueueBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploads = ref.watch(uploadNotifierProvider);
    if (uploads.isEmpty) return const SizedBox.shrink();

    return Container(
      color: AppTheme.bgCard,
      child: Column(
        children: uploads.map((task) => _UploadTaskTile(task: task)).toList(),
      ),
    );
  }
}

class _UploadTaskTile extends ConsumerWidget {
  final UploadTask task;
  const _UploadTaskTile({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isError = task.status == UploadStatus.failed;
    final isDone = task.status == UploadStatus.done;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Icon
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_statusIcon, color: _statusColor, size: 18),
          ),
          const SizedBox(width: 12),
          // Name + progress
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.fileName,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                if (!isDone && !isError)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: task.progress,
                      backgroundColor: AppTheme.bgSurface,
                      valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                      minHeight: 4,
                    ),
                  ),
                if (isError)
                  Text(task.errorMessage ?? 'Upload failed',
                      style: const TextStyle(color: AppTheme.error, fontSize: 11)),
                if (isDone)
                  const Text('Upload complete',
                      style: TextStyle(color: AppTheme.success, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Percentage or dismiss
          if (!isDone && !isError)
            Text('${(task.progress * 100).toInt()}%',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          if (isDone || isError)
            GestureDetector(
              onTap: () => ref.read(uploadNotifierProvider.notifier).dismissTask(task.uploadId),
              child: const Icon(Icons.close_rounded, color: AppTheme.textSecondary, size: 18),
            ),
        ],
      ),
    );
  }

  Color get _statusColor {
    switch (task.status) {
      case UploadStatus.uploading: return AppTheme.primary;
      case UploadStatus.done: return AppTheme.success;
      case UploadStatus.failed: return AppTheme.error;
      case UploadStatus.paused: return AppTheme.warning;
      default: return AppTheme.textSecondary;
    }
  }

  IconData get _statusIcon {
    switch (task.status) {
      case UploadStatus.uploading: return Icons.upload_rounded;
      case UploadStatus.done: return Icons.check_circle_rounded;
      case UploadStatus.failed: return Icons.error_rounded;
      case UploadStatus.paused: return Icons.pause_circle_rounded;
      default: return Icons.hourglass_empty_rounded;
    }
  }
}
