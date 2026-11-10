import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Flutter's widget test binding installs a blocking HttpClient override.
/// Initialize it before installing the suite-level override so API tests can
/// communicate only with their local HttpServer fixtures.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await HttpOverrides.runZoned(
    testMain,
    createHttpClient: (_) => HttpClient(),
  );
}
