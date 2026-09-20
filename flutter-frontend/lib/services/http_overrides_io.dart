import 'dart:io';

import 'package:flutter/foundation.dart';

/// Enables the development-only invalid-certificate bypass when explicitly
/// requested with --dart-define=ALLOW_BAD_CERTIFICATES=true.
void configureHttpOverrides() {
  const allowBadCertificates = bool.fromEnvironment(
    'ALLOW_BAD_CERTIFICATES',
    defaultValue: false,
  );

  if (!allowBadCertificates || !kDebugMode) {
    return;
  }

  HttpOverrides.global = _AllowBadCertificatesOverrides();
  debugPrint(
    'WARNING: TLS certificate verification is disabled for this debug run.',
  );
}

class _AllowBadCertificatesOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (certificate, host, port) => true;
    return client;
  }
}
