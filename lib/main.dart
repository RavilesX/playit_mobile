import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'constants/app_colors.dart';
import 'providers/player_provider.dart';
import 'screens/player_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const PlayItApp());
}

class PlayItApp extends StatelessWidget {
  const PlayItApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PlayerProvider()..initialize(),
      child: MaterialApp(
        title: 'Play It',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          textTheme: GoogleFonts.sairaStencilOneTextTheme(
            ThemeData.dark().textTheme,
          ),
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
