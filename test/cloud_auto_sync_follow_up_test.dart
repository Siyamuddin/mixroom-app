import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/cloud_auto_sync_follow_up.dart';

void main() {
  test('non-retryable failure never schedules an automatic follow-up', () {
    expect(
      cloudAutoSyncFollowUp(
        canAttempt: true,
        dirty: true,
        nonRetryableFailure: true,
        hasRetryDelay: false,
      ),
      CloudAutoSyncFollowUp.none,
    );
  });

  test('transient failure schedules its bounded delayed retry', () {
    expect(
      cloudAutoSyncFollowUp(
        canAttempt: true,
        dirty: true,
        nonRetryableFailure: false,
        hasRetryDelay: true,
      ),
      CloudAutoSyncFollowUp.delayed,
    );
  });

  test('newer dirty edit schedules one immediate follow-up', () {
    expect(
      cloudAutoSyncFollowUp(
        canAttempt: true,
        dirty: true,
        nonRetryableFailure: false,
        hasRetryDelay: false,
      ),
      CloudAutoSyncFollowUp.immediate,
    );
  });

  test('follow-up reasons are stable and cannot grow recursively', () {
    expect(
      cloudAutoSyncFollowUpReason(CloudAutoSyncFollowUp.immediate),
      'latest',
    );
    expect(cloudAutoSyncFollowUpReason(CloudAutoSyncFollowUp.delayed), 'retry');
    expect(cloudAutoSyncFollowUpReason(CloudAutoSyncFollowUp.none), isEmpty);
  });
}
