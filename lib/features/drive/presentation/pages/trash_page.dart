import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/drive_providers.dart';
import '../widgets/file_card.dart';

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
                Icon(Icons.delete_outline_rounded, color: AppTheme.textSecondary, size: 56),
                SizedBox(height: 16),
                Text('Trash is empty',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
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
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${files.length} item(s)',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  TextButton.icon(
                    onPressed: () => _emptyTrash(ref, files),
                    icon: const Icon(Icons.delete_forever_rounded, color: AppTheme.error, size: 16),
                    label: const Text('Empty Trash', style: TextStyle(color: AppTheme.error, fontSize: 13)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85,
                ),
                itemCount: files.length,
                itemBuilder: (_, i) => FileCard(file: files[i]),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      error: (e, _) => const SizedBox.shrink(),
    );
  }

  void _emptyTrash(WidgetRef ref, List files) {
    final repo = ref.read(fileRepositoryProvider);
    for (final file in files) {
      repo.permanentlyDelete(file);
    }
  }
}
