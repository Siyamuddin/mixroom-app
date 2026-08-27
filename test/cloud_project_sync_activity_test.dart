import 'package:flutter_test/flutter_test.dart';
import 'package:mixroom/helpers/project_manager.dart';

void main() {
  test(
    'cloud sync activity remains active until overlapping work completes',
    () {
      const projectId = 'cloud-sync-activity-test-project';

      ProjectManager.beginCloudProjectSync(projectId);
      ProjectManager.beginCloudProjectSync(projectId);
      expect(
        ProjectManager.cloudProjectSyncInFlight.value,
        contains(projectId),
      );

      ProjectManager.endCloudProjectSync(projectId);
      expect(
        ProjectManager.cloudProjectSyncInFlight.value,
        contains(projectId),
      );

      ProjectManager.endCloudProjectSync(projectId);
      expect(
        ProjectManager.cloudProjectSyncInFlight.value,
        isNot(contains(projectId)),
      );
    },
  );
}
