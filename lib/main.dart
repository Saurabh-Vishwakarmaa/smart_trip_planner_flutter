import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_trip_planner_flutter/authpages/loginpage.dart';
import 'package:smart_trip_planner_flutter/authpages/signuppage.dart';
import 'package:smart_trip_planner_flutter/presentations/screens/echo_screen.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(

      home: AgentScreen(),
    );
  }
}



