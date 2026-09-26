import 'package:flutter/cupertino.dart';

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
  EntryLineKind.note => CupertinoIcons.text_quote,
};
