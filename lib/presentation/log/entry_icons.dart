import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;

import 'entry_labels.dart';

/// The icon beside a line describing a logged day, the same wherever a day
/// is read back: on Today and in the calendar's day preview.
IconData entryLineIcon(EntryLineKind kind) => switch (kind) {
  EntryLineKind.flow => CupertinoIcons.drop,
  EntryLineKind.symptoms => CupertinoIcons.bandage,
  EntryLineKind.mood => CupertinoIcons.smiley,
  EntryLineKind.discharge => CupertinoIcons.drop_triangle,
  EntryLineKind.sex => CupertinoIcons.heart,
  EntryLineKind.pill => CupertinoIcons.capsule,
  EntryLineKind.temperature => CupertinoIcons.thermometer,
  EntryLineKind.ovulationTest => CupertinoIcons.lab_flask,
  // A test's two outcomes, rather than anything that reads as a verdict.
  EntryLineKind.pregnancyTest => CupertinoIcons.plus_slash_minus,
  EntryLineKind.note => CupertinoIcons.text_quote,
};

/// An icon beside a symptom or mood on the log sheet, so a row of options
/// can be scanned by shape before it is read. Null for anything without one,
/// which then shows its words alone.
IconData? entryIcon(String key) => switch (key) {
  'cramps' => Icons.waves_rounded,
  'headache' => Icons.psychology_alt_outlined,
  'backache' => Icons.accessibility_new_rounded,
  'bloating' => Icons.bubble_chart_outlined,
  'fatigue' => Icons.battery_1_bar_rounded,
  'nausea' => Icons.sick_outlined,
  'tenderBreasts' => Icons.favorite_border_rounded,
  'moodChange' => Icons.swap_vert_rounded,
  'acne' => Icons.grain_rounded,
  'troubleSleeping' => Icons.bedtime_outlined,
  'mood.calm' => Icons.spa_outlined,
  'mood.happy' => Icons.sentiment_very_satisfied_rounded,
  'mood.energetic' => Icons.bolt_rounded,
  'mood.sensitive' => Icons.water_drop_outlined,
  'mood.sad' => Icons.sentiment_dissatisfied_rounded,
  'mood.anxious' => Icons.cyclone_rounded,
  'mood.irritable' => Icons.sentiment_very_dissatisfied_rounded,
  'mood.lowEnergy' => Icons.snooze_rounded,
  _ => null,
};
