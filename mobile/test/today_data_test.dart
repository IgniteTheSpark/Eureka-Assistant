import 'package:flutter_test/flutter_test.dart';
import 'package:eureka/today/today_data.dart';

void main() {
  final now = DateTime(2026, 6, 22, 15, 0); // 15:00

  ChainItem ev(String id, DateTime at) =>
      ChainItem(kind: 'event', id: id, title: id, at: at, timed: true);
  ChainItem timedTodo(String id, DateTime at) =>
      ChainItem(kind: 'todo', id: id, title: id, at: at, timed: true);
  ChainItem noClockTodo(String id) => ChainItem(
      kind: 'todo', id: id, title: id, at: now, timed: false);

  group('splitChain', () {
    test('upcoming timed event → chain', () {
      final r = splitChain([ev('e1', now.add(const Duration(hours: 1)))], now);
      expect(r.chain.map((e) => e.id), ['e1']);
      expect(r.noTime, isEmpty);
    });

    test('past timed todo (due 14:00, now 15:00) → dropped', () {
      final r = splitChain([timedTodo('t1', DateTime(2026, 6, 22, 14, 0))], now);
      expect(r.chain, isEmpty);
      expect(r.noTime, isEmpty);
    });

    test('no-clock todo → noTime', () {
      final r = splitChain([noClockTodo('t2')], now);
      expect(r.chain, isEmpty);
      expect(r.noTime.map((e) => e.id), ['t2']);
    });

    test('chain is sorted ascending by time', () {
      final r = splitChain([
        ev('late', now.add(const Duration(hours: 3))),
        ev('soon', now.add(const Duration(minutes: 30))),
      ], now);
      expect(r.chain.map((e) => e.id), ['soon', 'late']);
    });

    test('in-progress event (started 10m ago, ends in 50m) stays, sorts first', () {
      final inProgress = ChainItem(
          kind: 'event',
          id: 'now',
          title: 'now',
          at: now.subtract(const Duration(minutes: 10)),
          timed: true,
          dur: const Duration(hours: 1));
      final r = splitChain([ev('later', now.add(const Duration(hours: 2))), inProgress], now);
      expect(r.chain.map((e) => e.id), ['now', 'later']);
    });

    test('event whose end already passed → dropped', () {
      final ended = ChainItem(
          kind: 'event',
          id: 'ended',
          title: 'ended',
          at: now.subtract(const Duration(hours: 2)),
          timed: true,
          dur: const Duration(hours: 1));
      expect(splitChain([ended], now).chain, isEmpty);
    });
  });
}
