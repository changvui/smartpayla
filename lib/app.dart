import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
import 'theme.dart';

class SmartPayLaApp extends StatelessWidget {
  const SmartPayLaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartPayLA',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomeShell(),
    );
  }
}
