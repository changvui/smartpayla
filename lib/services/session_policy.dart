import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/firebase_config.dart';

/// Starts Firebase, then either restores or deliberately forgets the session.
///
/// On the web the Firebase default keeps the user signed in across browser
/// restarts, which is wrong for an agent tool on a shared or borrowed machine:
/// closing the browser must end the session. Native builds keep the usual
/// persistent session, because a phone is a personal device and re-authenticating
/// every morning is friction without a benefit.
Future<void> configureAuthPersistence() async {
  if (!FirebaseRuntime.initialized) return;
  if (!kIsWeb) return;
  try {
    await FirebaseAuth.instance.setPersistence(Persistence.SESSION);
  } catch (error) {
    debugPrint('Could not set the web auth persistence: $error');
  }
}

/// True when the app was opened through a customer statement link. Such a visit
/// must never show the agent application, even if an agent session is still
/// stored on the device.
bool get isCustomerVisit {
  final token = Uri.base.queryParameters['s'];
  return token != null && token.isNotEmpty;
}

/// Optional credential for demos, kept out of the UI.
Future<void> signInForDemoIfConfigured() async {
  const email = String.fromEnvironment('DEMO_AUTH_EMAIL');
  const password = String.fromEnvironment('DEMO_AUTH_PASSWORD');
  if (email.isEmpty || password.isEmpty) return;
  try {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  } catch (error) {
    debugPrint('Demo auth sign-in failed: $error');
  }
}

/// Clears a stored agent session when a customer opens a statement link.
///
/// This is the strongest form of the least-privilege rule available in a single
/// bundle: a customer link signs the device out, so Back cannot reveal an agent
/// dashboard and the statement is served by the same anonymous path the rules
/// already allow.
Future<void> signOutForCustomerVisit() async {
  if (!FirebaseRuntime.initialized) return;
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    await FirebaseAuth.instance.signOut();
  } catch (error) {
    debugPrint('Could not sign out for a customer visit: $error');
  }
}
