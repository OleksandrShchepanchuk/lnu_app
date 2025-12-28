import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:lnu_nav_app/components/layouts/basic_layout/basic_layout.dart';
import 'package:lnu_nav_app/components/ui/future_loading.dart';
import 'package:lnu_nav_app/providers.dart';
import 'package:lnu_nav_app/services/update_service.dart';
import 'package:lnu_nav_app/store/permanent/config-storage.dart';
import 'package:lnu_nav_app/variables.dart';

const overlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  systemNavigationBarColor: Colors.black,
  statusBarIconBrightness: Brightness.light,
  systemNavigationBarIconBrightness: Brightness.light,
);

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LnuNav',
      theme: ThemeData(
        scaffoldBackgroundColor: backgroundColor,
        fontFamily: GoogleFonts.montserrat().fontFamily,
        colorScheme: const ColorScheme.dark(),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: FutureLoading(
          loadingText: 'Initializing Configuration...',
          future: ConfigStorage.initialize(),
          builder: (context, config) {
            return const BasicLayout();
          },
        ),
      ),
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  MapUpdateService().updateMapDatabase().then((_) {
    debugPrint("Background map update check finished");
  });

  runApp(
    const Providers(
      child: MyApp(),
    ),
  );
}