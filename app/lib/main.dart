import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PoGetItApp());
}

class PoGetItApp extends StatelessWidget {
  const PoGetItApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PoGetIt',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D6B),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F8), // light grey so white cards stand out
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF4F6F8),
          titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1B2B27)),
        ),
      ),
      home: const StartupGate(),
    );
  }
}

/// Initialises Firebase and signs in anonymously before showing the home screen.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late Future<void> _ready = _init();

  Future<void> _init() async {
    // On Android, Firebase reads its config from android/app/google-services.json.
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously(); // same uid is kept across restarts
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _ready,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Sign-in failed. Check your internet connection.\n\n${snap.error}',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: () => setState(() => _ready = _init()), child: const Text('Retry')),
                ]),
              ),
            ),
          );
        }
        return const HomeScreen();
      },
    );
  }
}
