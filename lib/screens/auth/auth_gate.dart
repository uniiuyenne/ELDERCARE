import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import 'login_screen.dart';

class AuthGate extends StatelessWidget {
  AuthGate({super.key, required this.signedInBuilder, AuthService? authService})
    : _authService = authService ?? AuthService();

  final Widget Function(BuildContext context, User user) signedInBuilder;
  final AuthService _authService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return LoginScreen();
        }

        return signedInBuilder(context, user);
      },
    );
  }
}
