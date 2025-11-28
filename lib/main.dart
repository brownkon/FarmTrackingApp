// (imports for low-level I/O removed)

import 'package:english_words/english_words.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:background_locator_2/background_locator.dart';
import 'package:background_locator_2/settings/android_settings.dart';
import 'package:background_locator_2/settings/ios_settings.dart';
import 'package:background_locator_2/settings/locator_settings.dart';
 import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'location_callback_handler.dart';
import 'history_page.dart';
import 'big_card.dart';
import "package:supabase_flutter/supabase_flutter.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
     url: 'https://qxzqmuenmaoggyphkfcy.supabase.co',
     anonKey: dotenv.env["supabaseAnonKey"] ?? '');
  final supabase = Supabase.instance.client;
  await supabase.auth.signInAnonymously();  
  await BackgroundLocator.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'Namer App',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        ),
        home: MyHomePage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  // --- existing word pair stuff ---
  var current = WordPair.random();

  void getNext() {
    current = WordPair.random();
    notifyListeners();
  }

  var favorites = <WordPair>[];

  void toggleFavorite() {
    if (favorites.contains(current)) {
      favorites.remove(current);
    } else {
      favorites.add(current);
    }
    notifyListeners();
  }

  // --- background GPS tracking state ---
  bool isBgTracking = false;

  Future<void> startBackgroundTracking() async {
    if (isBgTracking) return;

    debugPrint('startBackgroundTracking: registering location updates...');

    try {
      await BackgroundLocator.registerLocationUpdate(
        LocationCallbackHandler.callback,
        initCallback: LocationCallbackHandler.initCallback,
        disposeCallback: LocationCallbackHandler.disposeCallback,
        autoStop: false,
        iosSettings: const IOSSettings(
          accuracy: LocationAccuracy.HIGH,
          distanceFilter: 10, // meters (lower for more frequent updates during testing)
        ),
        androidSettings: const AndroidSettings(
          accuracy: LocationAccuracy.HIGH,
          interval: 10,       // seconds between updates (for testing)
          distanceFilter: 10, // meters
          androidNotificationSettings: AndroidNotificationSettings(
            notificationChannelName: 'GPS Tracking',
            notificationTitle: 'Background location is ON',
            notificationMsg: 'We are tracking your location.',
            notificationBigMsg:
                'Background location tracking is active. You can stop it from inside the app.',
          ),
        ),
      );

      isBgTracking = true;
      debugPrint('startBackgroundTracking: SUCCESS');
      notifyListeners();
    } catch (e, st) {
      debugPrint('startBackgroundTracking ERROR: $e');
      debugPrint('$st');
    }
  }

  Future<void> stopBackgroundTracking() async {
    debugPrint('stopBackgroundTracking: unregistering location updates...');
    await BackgroundLocator.unRegisterLocationUpdate();
    isBgTracking = false;
    notifyListeners();
    debugPrint('stopBackgroundTracking: DONE');
  }
}

class FavoritesPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    if (appState.favorites.isEmpty) {
      return Center(
        child: Text('No favorites yet.'),
      );
    }

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text('You have '
              '${appState.favorites.length} favorites:'),
        ),
        for (var pair in appState.favorites)
          ListTile(
            leading: Icon(Icons.favorite),
            title: Text(pair.asLowerCase),
          ),
      ],
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    Widget page;
    switch (selectedIndex) {
      case 0:
        page = GeneratorPage();
        break;
      case 1:
        page = FavoritesPage();
        break;
      case 2:
        page = const HistoryPage();
        break;
      default:
        throw UnimplementedError('no widget for $selectedIndex');
    }

    return LayoutBuilder(builder: (context, constraints) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: NavigationRail(
                extended: constraints.maxWidth >= 600,  // ← Here.
                destinations: [
                  const NavigationRailDestination(
                    icon: Icon(Icons.home),
                    label: Text('Home'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.favorite),
                    label: Text('Favorites'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.history),
                    label: Text('History'),
                  ),
                ],
                selectedIndex: selectedIndex,
                onDestinationSelected: (value) {
                  setState(() {
                    selectedIndex = value;
                  });
                },
              ),
            ),
            Expanded(
              child: Container(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: page,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class GeneratorPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    var pair = appState.current;

    IconData icon;
    if (appState.favorites.contains(pair)) {
      icon = Icons.favorite;
    } else {
      icon = Icons.favorite_border;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BigCard(pair: pair),
          SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  appState.toggleFavorite();
                },
                icon: Icon(icon),
                label: Text('Like'),
              ),
              SizedBox(width: 10),
              ElevatedButton(
                onPressed: () {
                  appState.getNext();
                },
                child: Text('Next'),
              ),
            ],
          ),
          const SizedBox(height: 40),

            // --- Background GPS controls ---
            Text(
              'Background GPS',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              appState.isBgTracking
                  ? 'Background tracking: ON'
                  : 'Background tracking: OFF',
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                debugPrint("BUTTON PRESSED");
                if (appState.isBgTracking) {
                  appState.stopBackgroundTracking();
                } else {
                  appState.startBackgroundTracking();
                }
              },
              child: Text(
                appState.isBgTracking
                    ? 'Stop background tracking'
                    : 'Start background tracking',
              ),
            ),
        ],
      ),
    );
  }
}
