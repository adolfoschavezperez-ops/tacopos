enum AppUpdateSeverity { none, recommended, required }

class AppUpdatePolicyInput {
  const AppUpdatePolicyInput({
    required this.currentVersionCode,
    required this.minimumSupportedVersionCode,
    required this.recommendedVersionCode,
    required this.forceUpdate,
    required this.updateMessage,
  });

  final int currentVersionCode;
  final int minimumSupportedVersionCode;
  final int recommendedVersionCode;
  final bool forceUpdate;
  final String updateMessage;
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
}

AppUpdateDecision evaluateAppUpdatePolicy(AppUpdatePolicyInput input) {
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
