// PlayIt Mobile — multi-stem audio player.
// Copyright (C) 2026 RavilesX
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
