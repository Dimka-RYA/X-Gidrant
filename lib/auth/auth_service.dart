import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Получение текущего пользователя
  User? get currentUser => _auth.currentUser;

  // Stream изменений состояния авторизации
  Stream<User?> get user => _auth.authStateChanges();

  // Ключи для хранения данных в SharedPreferences
  static const _userRoleKey = 'userRole';
  
  // Получение экземпляра SharedPreferences
  Future<SharedPreferences> get _prefs async => await SharedPreferences.getInstance();
  
  // Получение роли пользователя
  Future<String?> getUserRole() async {
    final prefs = await _prefs;
    return prefs.getString(_userRoleKey);
  }
  
  // Сохранение роли пользователя
  Future<void> _saveUserRole(String role) async {
    final prefs = await _prefs;
    await prefs.setString(_userRoleKey, role);
  }
  
  // Аутентификация пользователя
  Future<bool> signIn(String email, String password) async {
    try {
      // Пробуем войти через Firebase
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Если пользователь успешно вошел
      if (result.user != null) {
        await _saveUserRole('user');
        return true;
      }
      return false;
    } catch (e) {
      print('Ошибка при входе: $e');
      
      try {
        // Для тестирования разрешаем вход с тестовыми данными
        if (email == 'test@example.com' && password == 'password') {
          await _saveUserRole('user');
          return true;
        }
        
        // Можно добавить больше тестовых пользователей при необходимости
        if (email == 'zalupa@chlen.ru' && password == 'password123') {
          await _saveUserRole('user');
          return true;
        }
      } catch (innerError) {
        print('Внутренняя ошибка при тестовом входе: $innerError');
      }
      
      return false;
    }
  }
  
  // Регистрация пользователя
  Future<bool> register(String email, String password) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      if (result.user != null) {
        // При регистрации всегда назначаем роль "user"
        await _saveUserRole('user');
        return true;
      }
      return false;
    } catch (e) {
      print('Ошибка при регистрации: $e');
      return false;
    }
  }
  
  // Выход из аккаунта
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      
      // Удаляем данные о роли пользователя
      final prefs = await _prefs;
      await prefs.remove(_userRoleKey);
    } catch (e) {
      print('Ошибка при выходе: $e');
    }
  }
  
  // Проверка авторизации
  Future<bool> isLoggedIn() async {
    return _auth.currentUser != null;
  }
} 