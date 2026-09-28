import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

class PastureWalkApp extends StatelessWidget {
  const PastureWalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PastureWalk',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          toolbarHeight: 48,
          centerTitle: false,
          titleSpacing: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
