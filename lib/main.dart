import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_config.dart';
import 'auth/login_screen.dart';
import 'auth/register_screen.dart';
import 'main_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Проверяем, не инициализирован ли Firebase уже
    List<FirebaseApp> apps = Firebase.apps;
    if (apps.isEmpty) {
      // Инициализация Firebase, если еще не инициализирован
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: FirebaseConfig.apiKey,
          appId: FirebaseConfig.appId,
          messagingSenderId: FirebaseConfig.messagingSenderId,
          projectId: FirebaseConfig.projectId,
          authDomain: FirebaseConfig.authDomain,
          storageBucket: FirebaseConfig.storageBucket,
          measurementId: FirebaseConfig.measurementId,
        ),
      );
    } else {
      Firebase.app(); // Используем уже инициализированное приложение
    }
    print("Firebase успешно инициализирован");
  } catch (e) {
    print("Ошибка инициализации Firebase: $e");
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'X-Гидрант',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: _getLandingPage(),
      routes: {
        '/login': (context) {
          print('Переход на экран входа');
          return const LoginScreen();
        },
        '/register': (context) {
          print('Переход на экран регистрации');
          return const RegisterScreen();
        },
        '/main': (context) {
          print('Переход на главный экран');
          return const MainScreen();
        },
      },
    );
  }
  
  Widget _getLandingPage() {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Если подключение активно и у нас есть пользователь
        if (snapshot.connectionState == ConnectionState.active) {
          User? user = snapshot.data;
          if (user == null) {
            print('Пользователь не авторизован, показываем экран входа');
            return const LoginScreen();
          }
          
          print('Пользователь авторизован (${user.email}), показываем главный экран');
          return const MainScreen();
        }
        
        // Если подключение не установлено, показываем экран загрузки
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('X-Gidrant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthService().signOut();
            },
          ),
        ],
      ),
      body: const Center(
        child: Text('Вы успешно вошли в систему!'),
      ),
    );
  }
}
