import 'package:flutter/material.dart';

const Color kPanel = Color(0xFF2A2A2A);
const Color kTan = Color(0xFF3B3830);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFF1E1E1E),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFB8A98A),
      brightness: Brightness.dark,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Color(0xFF3A3A3A),
      border: OutlineInputBorder(borderSide: BorderSide.none),
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    ),
  );
}
