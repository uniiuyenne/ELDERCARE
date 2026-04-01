import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'services/firebase_bootstrap_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrapService.initialize();
  runApp(const MyApp());
}
