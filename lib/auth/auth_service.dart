import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Текущий пользователь
  Stream<User?> get user => _auth.authStateChanges();

  // Регистрация с помощью email и пароля
  Future<User?> registerWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } catch (e) {
      print('Ошибка при регистрации: $e');
      return null;
    }
  }

  // Вход с помощью email и пароля
  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result.user;
    } catch (e) {
      print('Ошибка при входе: $e');
      return null;
    }
  }

  // Выход
  Future<void> signOut() async {
    try {
      return await _auth.signOut();
    } catch (e) {
      print('Ошибка при выходе: $e');
    }
  }
} 