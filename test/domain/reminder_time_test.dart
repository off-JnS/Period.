import 'package:period/domain/models/reminder_time.dart';
import 'package:test/test.dart';

/// The wall-clock half of a reminder.
///
/// Runs on the plain Dart VM with no Flutter binding, which is the point of
/// CLAUDE.md section 2: this type exists because Flutter's `TimeOfDay` cannot
/// be imported here, and a test that needed a binding would prove the boundary
/// had been crossed.
void main() {
  group('construction', () {
    test('rejects an hour outside 0..23', () {
      expect(() => ReminderTime.checked(-1, 0), throwsArgumentError);
      expect(() => ReminderTime.checked(24, 0), throwsArgumentError);
    });

    test('rejects a minute outside 0..59', () {
      expect(() => ReminderTime.checked(20, -1), throwsArgumentError);
      expect(() => ReminderTime.checked(20, 60), throwsArgumentError);
    });

    test('accepts both ends of the day', () {
      expect(ReminderTime.checked(0, 0).minutesSinceMidnight, 0);
      expect(ReminderTime.checked(23, 59).minutesSinceMidnight, 1439);
    });

    test('does not wrap 24:00 round to the previous midnight', () {
      // Wrapping would move a reminder a whole day earlier, silently. Section
      // 3's reason for CycleDate rejecting 2023-02-29 rather than normalising
      // it applies here for the same reason.
      expect(() => ReminderTime.checked(24, 0), throwsArgumentError);
    });
  });

  group('ordering', () {
    test('compares by time of day', () {
      expect(
        const ReminderTime(9, 30).isBefore(const ReminderTime(20, 0)),
        isTrue,
      );
      expect(
        const ReminderTime(20, 0).isAfter(const ReminderTime(9, 30)),
        isTrue,
      );
    });

    test('is neither before nor after itself', () {
      const time = ReminderTime(20, 0);
      expect(time.isBefore(time), isFalse);
      expect(time.isAfter(time), isFalse);
    });

    test('orders minutes within the same hour', () {
      // A comparison on the hour alone would call these equal, and a reminder
      // set for 20:45 would fire as though it were 20:00.
      expect(
        const ReminderTime(20, 15).isBefore(const ReminderTime(20, 45)),
        isTrue,
      );
    });

    test('sorts', () {
      final times = [
        const ReminderTime(23, 59),
        const ReminderTime(0, 0),
        const ReminderTime(20, 30),
        const ReminderTime(20, 0),
      ]..sort();
      expect(times.map((time) => time.toHhMm()).toList(), [
        '00:00',
        '20:00',
        '20:30',
        '23:59',
      ]);
    });
  });

  group('HH:mm', () {
    test('zero pads both halves', () {
      expect(const ReminderTime(9, 5).toHhMm(), '09:05');
      expect(const ReminderTime(0, 0).toHhMm(), '00:00');
    });

    test('round trips', () {
      for (final time in [
        const ReminderTime(0, 0),
        const ReminderTime(9, 5),
        const ReminderTime(20, 0),
        const ReminderTime(23, 59),
      ]) {
        expect(ReminderTime.parseHhMm(time.toHhMm()), time);
      }
    });

    test('rejects anything that is not HH:mm', () {
      for (final malformed in [
        '',
        '8:00',
        '20:0',
        '2000',
        'evening',
        '20:00:00',
      ]) {
        expect(
          () => ReminderTime.parseHhMm(malformed),
          throwsFormatException,
          reason: malformed,
        );
      }
    });

    test('rejects a well formed string that is not a real time', () {
      expect(() => ReminderTime.parseHhMm('25:00'), throwsFormatException);
      expect(() => ReminderTime.parseHhMm('20:60'), throwsFormatException);
    });
  });

  group('equality', () {
    test('two times with the same clock reading are equal', () {
      expect(const ReminderTime(20, 0), const ReminderTime(20, 0));
      expect(
        const ReminderTime(20, 0).hashCode,
        const ReminderTime(20, 0).hashCode,
      );
    });

    test('differs on the minute alone', () {
      expect(const ReminderTime(20, 0), isNot(const ReminderTime(20, 1)));
    });

    test('works as a set member', () {
      // Built two different ways on purpose. Two identical const literals are
      // canonicalised to the same instance, so a set of those collapses to one
      // whether or not == is implemented at all -- the analyzer says as much.
      // Going through the checked factory makes it a real equality test.
      final times = [const ReminderTime(20, 0), ReminderTime.checked(20, 0)];

      expect(identical(times.first, times.last), isFalse);
      expect(times.toSet(), hasLength(1));
    });
  });
}
