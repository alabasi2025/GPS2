import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/session_controller.dart';
import 'services/simulated_gnss_source.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const PointGpsApp());
}

class PointGpsApp extends StatefulWidget {
  const PointGpsApp({super.key});

  @override
  State<PointGpsApp> createState() => _PointGpsAppState();
}

class _PointGpsAppState extends State<PointGpsApp> with WidgetsBindingObserver {
  late final SessionController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // على الويب لا GNSS خام ولا قنوات Android → محاكاة واقعية للمعاينة فقط.
    _controller = SessionController(service: kIsWeb ? SimulatedGnssSource() : null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.init());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller.onResumed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نقطة',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: HomeScreen(controller: _controller),
    );
  }
}
