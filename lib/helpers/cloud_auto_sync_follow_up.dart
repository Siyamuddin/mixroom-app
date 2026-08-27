enum CloudAutoSyncFollowUp { none, immediate, delayed }

CloudAutoSyncFollowUp cloudAutoSyncFollowUp({
  required bool canAttempt,
  required bool dirty,
  required bool nonRetryableFailure,
  required bool hasRetryDelay,
}) {
  if (!canAttempt || nonRetryableFailure) {
    return CloudAutoSyncFollowUp.none;
  }
  if (hasRetryDelay) {
    return CloudAutoSyncFollowUp.delayed;
  }
  return dirty ? CloudAutoSyncFollowUp.immediate : CloudAutoSyncFollowUp.none;
}

String cloudAutoSyncFollowUpReason(CloudAutoSyncFollowUp followUp) {
  return switch (followUp) {
    CloudAutoSyncFollowUp.none => '',
    CloudAutoSyncFollowUp.immediate => 'latest',
    CloudAutoSyncFollowUp.delayed => 'retry',
  };
}
