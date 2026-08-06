class CheckoutSubmissionGuard {
  bool _locked = false;

  bool get isLocked => _locked;

  bool acquire() {
    if (_locked) return false;
    _locked = true;
    return true;
  }

  void release() {
    _locked = false;
  }
}
