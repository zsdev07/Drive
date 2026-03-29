import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/drive_providers.dart';
import 'file_card.dart';

class FileGrid extends ConsumerWidget {
  final String? folderId;
  const FileGrid({super.key, this.folderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(filesProvider(folderId));
    final selectedUuids = ref.watch(selectionProvider);
    final isSelectionMode = selectedUuids.isNotEmpty;

    return filesAsync.when(
      data: (files) {
        if (files.isEmpty) return const _EmptyState();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Select-all row — only visible in selection mode
            if (isSelectionMode)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => ref
                          .read(selectionProvider.notifier)
                          .selectAll(files.map((f) => f.uuid).toList()),
                      icon: const Icon(Icons.select_all_rounded,
                          size: 16, color: AppTheme.primary),
                      label: const Text('Select All',
                          style: TextStyle(
                              color: AppTheme.primary, fontSize: 13)),
                    ),
                    const Spacer(),
                    Text(
                      '${selectedUuids.length} selected',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: files.length,
                itemBuilder: (_, i) => FileCard(file: files[i]),
              ),
            ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(
          child: CircularProgressIndicator(
            color: AppTheme.primary,
            strokeWidth: 2,
          ),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(20),
        child: Text('Error: $e',
            style: const TextStyle(color: AppTheme.error)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cloud_upload_rounded,
                color: AppTheme.primary, size: 40),
          ),
          const SizedBox(height: 20),
          const Text('No files yet',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 8),
          const Text(
            'Tap the upload button to add files\nto your ZX Drive',
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
