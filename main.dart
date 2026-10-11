import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'sign_in_screen.dart';
import 'seed_office.dart'; // TEMPORARY: remove after seeding
import 'backfill_doc_numbers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase connected successfully');

    // TEMPORARY: remove after the first successful run
    final count = await seedOffices();
    debugPrint('✅ Seeded $count offices');
  } catch (e) {
    debugPrint('❌ Firebase connection failed: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Document Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      home: const SignInScreen(),
    );
  }
}