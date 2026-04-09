import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

class PastureWalkApp extends StatelessWidget {
  const PastureWalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pasture Walk',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
