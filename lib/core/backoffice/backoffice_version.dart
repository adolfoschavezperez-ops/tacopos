class BackofficeVersion {
  const BackofficeVersion._();

  static const String version = '1.0.5';
  static const String label = 'Backoffice v$version';

  // Versioning convention:
  // PATCH: 1.0.0 -> 1.0.1 for small fixes.
  // MINOR: 1.0.0 -> 1.1.0 for important improvements or new features.
  // MAJOR: 1.x -> 2.0.0 for major changes.
}
