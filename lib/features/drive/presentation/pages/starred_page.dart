import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/drive_providers.dart';
import '../widgets/file_card.dart';

class StarredPage extends ConsumerWidget {
  const StarredPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(starredFilesProvider);
    return filesAsync.when(
      data: (files) {
        if (files.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_border_rounded, color: AppTheme.textSecondary, size: 56),
                SizedBox(height: 16),
                Text('No starred files',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                Text('Long press any file and tap Star',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ],
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85,
          ),
          itemCount: files.length,
          itemBuilder: (_, i) => FileCard(file: files[i]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}
