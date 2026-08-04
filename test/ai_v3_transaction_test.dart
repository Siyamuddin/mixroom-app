import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/ai/v3/ai_v3_transaction.dart';

class _IncompleteExecutionRollback
    implements Exception, AiV3RollbackIncompleteFailure {}

void main() {
  test('commits a completely verified bundle once', () async {
    final events = <String>[];
    final result = await const AiV3LocalTransaction<String, String>().run(
      executeAndCapture: () async {
        events.addAll(<String>['apply:a', 'apply:b']);
        return <String>['a', 'b'];
      },
      verify: () async => true,
      observe: () async => <String>['observed:a', 'observed:b'],
      rollback: (action) async => events.add('undo:$action'),
      commit: (actions) async => events.add('commit:${actions.join(',')}'),
    );

    expect(result.captured, <String>['a', 'b']);
    expect(result.observed, <String>['observed:a', 'observed:b']);
    expect(events, <String>['apply:a', 'apply:b', 'commit:a,b']);
  });

  test('accepts an already-satisfied verified bundle without an undo entry',
      () async {
    var commits = 0;
    final result = await const AiV3LocalTransaction<String, String>().run(
      executeAndCapture: () async => <String>[],
      verify: () async => true,
      observe: () async => <String>['already-satisfied'],
      rollback: (_) async {},
      commit: (_) async => commits += 1,
    );

    expect(result.captured, isEmpty);
    expect(result.observed, <String>['already-satisfied']);
    expect(commits, 0);
  });

  test('readback mismatch rolls back in reverse order', () async {
    final events = <String>[];

    await expectLater(
      const AiV3LocalTransaction<String, String>().run(
        executeAndCapture: () async => <String>['a', 'b', 'c'],
        verify: () async => false,
        observe: () async => <String>['mismatch'],
        rollback: (action) async => events.add('undo:$action'),
        commit: (_) async => events.add('commit'),
      ),
      throwsA(
        isA<AiV3TransactionFailure<String>>().having(
          (error) => error.rollbackIncomplete,
          'rollbackIncomplete',
          isFalse,
        ),
      ),
    );
    expect(events, <String>['undo:c', 'undo:b', 'undo:a']);
  });

  test('readback mismatch can delegate one atomic bulk rollback', () async {
    final events = <String>[];

    await expectLater(
      const AiV3LocalTransaction<String, String>().run(
        executeAndCapture: () async => <String>['a', 'b', 'c'],
        verify: () async => false,
        observe: () async => <String>['mismatch'],
        rollback: (action) async => events.add('single:$action'),
        rollbackAll: (actions) async {
          events.add('bulk:${actions.join(',')}');
        },
        commit: (_) async => events.add('commit'),
      ),
      throwsA(
        isA<AiV3TransactionFailure<String>>().having(
          (error) => error.rollbackIncomplete,
          'rollbackIncomplete',
          isFalse,
        ),
      ),
    );
    expect(events, <String>['bulk:a,b,c']);
  });

  test('failed bulk rollback is reported as incomplete', () async {
    await expectLater(
      const AiV3LocalTransaction<String, String>().run(
        executeAndCapture: () async => <String>['a'],
        verify: () async => false,
        observe: () async => <String>['mismatch'],
        rollback: (_) async {},
        rollbackAll: (_) async => throw StateError('bulk rollback failed'),
        commit: (_) async {},
      ),
      throwsA(
        isA<AiV3TransactionFailure<String>>().having(
          (error) => error.rollbackIncomplete,
          'rollbackIncomplete',
          isTrue,
        ),
      ),
    );
  });

  test('commit failure rolls back and reports an incomplete rollback',
      () async {
    final events = <String>[];

    await expectLater(
      const AiV3LocalTransaction<String, String>().run(
        executeAndCapture: () async => <String>['a', 'b'],
        verify: () async => true,
        observe: () async => <String>['ok'],
        rollback: (action) async {
          events.add('undo:$action');
          if (action == 'a') throw StateError('undo failed');
        },
        commit: (_) async => throw StateError('commit failed'),
      ),
      throwsA(
        isA<AiV3TransactionFailure<String>>().having(
          (error) => error.rollbackIncomplete,
          'rollbackIncomplete',
          isTrue,
        ),
      ),
    );
    expect(events, <String>['undo:b', 'undo:a']);
  });

  test('execution failure relies on capture rollback and never double-undoes',
      () async {
    var rollbackCalls = 0;

    await expectLater(
      const AiV3LocalTransaction<String, String>().run(
        executeAndCapture: () async => throw StateError('apply failed'),
        verify: () async => true,
        observe: () async => <String>[],
        rollback: (_) async => rollbackCalls += 1,
        commit: (_) async {},
      ),
      throwsA(isA<AiV3TransactionFailure<String>>()),
    );
    expect(rollbackCalls, 0);
  });

  test('preserves rollback-incomplete status from the execution layer',
      () async {
    await expectLater(
      const AiV3LocalTransaction<String, String>().run(
        executeAndCapture: () async => throw _IncompleteExecutionRollback(),
        verify: () async => true,
        observe: () async => <String>[],
        rollback: (_) async {},
        commit: (_) async {},
      ),
      throwsA(
        isA<AiV3TransactionFailure<String>>().having(
          (error) => error.rollbackIncomplete,
          'rollbackIncomplete',
          isTrue,
        ),
      ),
    );
  });
}
