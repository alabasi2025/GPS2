import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/session_controller.dart';
import 'services/simulated_gnss_source.dart';
import 'services/update_service.dart';
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
  late final UpdateService _updates;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // على الويب لا GNSS خام ولا قنوات Android → محاكاة واقعية للمعاينة فقط.
    _controller = SessionController(service: kIsWeb ? SimulatedGnssSource() : null);
    _updates = UpdateService();
    // فحص صامت عند الإقلاع (بلا تنزيل) حتى تظهر شارة «تحديث» إن وُجد.
    if (!kIsWeb) WidgetsBinding.instance.addPostFrameCallback((_) => _updates.check());
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
    _updates.dispose();
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
      home: HomeScreen(controller: _controller, updates: _updates),
    );
  }
}
