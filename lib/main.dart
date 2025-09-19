import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smart_trip_planner_flutter/data/local/local_store.dart';
import 'package:smart_trip_planner_flutter/presentations/screens/echo_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalStore.instance.init(); // Hive init/open
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF10B981));
    return MaterialApp(
      title: 'Smart Trip Planner',
      theme: base.copyWith(
        textTheme: GoogleFonts.interTextTheme(base.textTheme),
        appBarTheme: base.appBarTheme.copyWith(
          titleTextStyle: GoogleFonts.inter(textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black)),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F8F8),
      ),
      home: const AgentScreen(),
    );
  }
}



