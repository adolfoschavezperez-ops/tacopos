enum AppUpdateSeverity { none, recommended, required }

enum DeviceUpdateStatus { upToDate, updateRecommended, updateRequired, unknown }

class AppUpdatePolicyInput {
  const AppUpdatePolicyInput({
    required this.currentVersionCode,
    required this.minimumSupportedVersionCode,
    required this.recommendedVersionCode,
    required this.forceUpdate,
    required this.updateMessage,
    this.active = true,
    this.rolloutGroup,
    this.enabledRolloutGroups = const [],
  });

  final int currentVersionCode;
  final int minimumSupportedVersionCode;
  final int recommendedVersionCode;
  final bool forceUpdate;
  final String updateMessage;
  final bool active;
  final String? rolloutGroup;
  final List<String> enabledRolloutGroups;
}

class AppUpdateDecision {
  const AppUpdateDecision({
    required this.severity,
    required this.message,
    required this.canContinue,
  });

  final AppUpdateSeverity severity;
  final String message;
  final bool canContinue;

  bool get isRequired => severity == AppUpdateSeverity.required;
  bool get isRecommended => severity == AppUpdateSeverity.recommended;

  DeviceUpdateStatus get deviceStatus {
    return switch (severity) {
      AppUpdateSeverity.none => DeviceUpdateStatus.upToDate,
      AppUpdateSeverity.recommended => DeviceUpdateStatus.updateRecommended,
      AppUpdateSeverity.required => DeviceUpdateStatus.updateRequired,
    };
  }
}

AppUpdateDecision evaluateAppUpdatePolicy(AppUpdatePolicyInput input) {
  if (!input.active || !_rolloutApplies(input)) {
    return const AppUpdateDecision(
      severity: AppUpdateSeverity.none,
      message: '',
      canContinue: true,
    );
  }
  final message = input.updateMessage.trim().isEmpty
      ? 'Hay una nueva version de TacoPOS disponible.'
      : input.updateMessage.trim();
  if (input.currentVersionCode < input.minimumSupportedVersionCode ||
      (input.forceUpdate &&
          input.currentVersionCode < input.recommendedVersionCode)) {
    return AppUpdateDecision(
      severity: AppUpdateSeverity.required,
      message: message,
      canContinue: false,
    );
  }
  if (input.currentVersionCode < input.recommendedVersionCode) {
    return AppUpdateDecision(
      severity: AppUpdateSeverity.recommended,
      message: message,
      canContinue: true,
    );
  }
  return const AppUpdateDecision(
    severity: AppUpdateSeverity.none,
    message: '',
    canContinue: true,
  );
}

bool _rolloutApplies(AppUpdatePolicyInput input) {
  final enabledGroups = input.enabledRolloutGroups
      .map((group) => group.trim())
      .where((group) => group.isNotEmpty)
      .toSet();
  if (enabledGroups.isEmpty) return true;
  final deviceGroup = input.rolloutGroup?.trim();
  if (deviceGroup == null || deviceGroup.isEmpty) return false;
  return enabledGroups.contains(deviceGroup);
}

String deviceUpdateStatusName(DeviceUpdateStatus status) {
  return switch (status) {
    DeviceUpdateStatus.upToDate => 'up_to_date',
    DeviceUpdateStatus.updateRecommended => 'update_recommended',
    DeviceUpdateStatus.updateRequired => 'update_required',
    DeviceUpdateStatus.unknown => 'unknown',
  };
}

DeviceUpdateStatus parseDeviceUpdateStatus(String? value) {
  return switch (value) {
    'up_to_date' => DeviceUpdateStatus.upToDate,
    'update_recommended' => DeviceUpdateStatus.updateRecommended,
    'update_required' => DeviceUpdateStatus.updateRequired,
    _ => DeviceUpdateStatus.unknown,
  };
}
