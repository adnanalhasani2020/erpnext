import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Restore real HTTP clients for loopback HttpServer fixtures in API tests.
/// Flutter's test binding otherwise replaces HttpClient with a 400-only client.
class _LoopbackHttpOverrides extends HttpOverrides {}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _LoopbackHttpOverrides();
  await testMain();
}
