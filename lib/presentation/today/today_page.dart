import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final data = ref.watch(todayViewDataProvider);
    // The date does not depend on the database, so the heading is the same
    // whether the read succeeded, failed or has not finished. Falling back to
    // the screen's name in those two branches would make the app bar flicker
    // from a word to a date on every cold start.
    final heading = formatTodayHeading(
      context,
      ref.watch(clockProvider).today(),
    );

    return data.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(heading)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(title: Text(heading)),
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
