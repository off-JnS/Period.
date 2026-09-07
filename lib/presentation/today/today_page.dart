import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../data_error.dart';
import '../log_day.dart';
import '../providers.dart';
import 'today_screen.dart';

/// The Today screen connected to the database.
///
/// Kept separate from [TodayScreen], which stays a pure function of its input so
/// that every state can be rendered in a golden file without a database. This
/// is the thin layer that reads real data and writes it back.
class TodayPage extends ConsumerWidget {
  /// Creates the page.
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final data = ref.watch(todayViewDataProvider);

    return data.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l10n.todayTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(title: Text(l10n.todayTitle)),
        body: DataErrorPanel(
          onRetry: () => ref.invalidate(periodStartsProvider),
        ),
      ),
      data: (view) => TodayScreen(
        data: view,
        onLogToday: () => logDay(context, ref, ref.read(clockProvider).today()),
      ),
    );
  }
}
