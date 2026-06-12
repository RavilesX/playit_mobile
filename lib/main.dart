import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'constants/app_colors.dart';
import 'providers/player_provider.dart';
import 'screens/player_screen.dart';
import 'services/audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  final provider = PlayerProvider();
  // Media session must be registered before the first frame so the
  // notification can appear as soon as playback starts.
  await initPlayItAudioHandler(provider);
  unawaited(provider.initialize());

  runApp(PlayItApp(provider: provider));
}

class PlayItApp extends StatelessWidget {
  final PlayerProvider provider;
  const PlayItApp({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        title: 'Play It',
        debugShowCheckedModeBanner: false,
        // Cap system font scaling so fixed layouts don't overflow
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3),
            ),
            child: child!,
          );
        },
        theme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'SairaStencilOne',
          scaffoldBackgroundColor: AppColors.background,
          colorScheme: const ColorScheme.dark(
            primary: AppColors.accentBlue,
            secondary: AppColors.accentPurple,
            surface: AppColors.surface,
          ),
          drawerTheme: const DrawerThemeData(
            backgroundColor: Colors.transparent,
          ),
          sliderTheme: const SliderThemeData(
            activeTrackColor: AppColors.accentPurple,
            inactiveTrackColor: AppColors.progressInactive,
            thumbColor: Colors.white,
          ),
          tabBarTheme: const TabBarThemeData(
            labelColor: AppColors.accentBlue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.accentPurple,
          ),
        ),
        home: const PlayerScreen(),
      ),
    );
  }
}
