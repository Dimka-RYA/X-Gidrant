import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // Статическая переменная для сохранения роли текущей сессии
  static String? _currentSessionRole;

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
    // Сначала проверяем роль в текущей сессии
    if (_currentSessionRole != null) {
      print('Получена роль из текущей сессии: $_currentSessionRole');
      return _currentSessionRole;
    }
    
    try {
      final prefs = await _prefs;
      final role = prefs.getString(_userRoleKey);
      print('Получена роль из SharedPreferences: $role');
      
      // Сохраняем в текущей сессии
      _currentSessionRole = role;
      return role;
    } catch (e) {
      print('Ошибка при получении роли: $e');
      return null;
    }
  }
  
  // Публичный метод для сохранения роли пользователя
  Future<void> saveUserRole(String role) async {
    print('Публичный вызов сохранения роли: $role');
    await _saveUserRole(role);
  }
  
  // Сохранение роли пользователя
  Future<void> _saveUserRole(String role) async {
    print('Сохранение роли: $role');
    // Сохраняем в статической переменной для текущей сессии
    _currentSessionRole = role;
    
    try {
      final prefs = await _prefs;
      await prefs.setString(_userRoleKey, role);
      print('Роль успешно сохранена в SharedPreferences: $role (ключ: $_userRoleKey)');
    } catch (e) {
      print('Ошибка при сохранении роли: $e');
    }
  }
  
  // Проверяет, является ли текущий пользователь инженером
  Future<bool> isEngineer() async {
    print('================================================================');
    print('ПРОВЕРКА РОЛИ ИНЖЕНЕРА (НАЧАЛО)');
    final user = currentUser;
    if (user == null) {
      print('ПРОВЕРКА РОЛИ: Ошибка - пользователь не авторизован');
      print('================================================================');
      return false;
    }
    
    print('ПРОВЕРКА РОЛИ: UID пользователя: ${user.uid}');
    print('ПРОВЕРКА РОЛИ: Email пользователя: ${user.email}');
    
    try {
      // Проверяем роль в Firestore (приоритетный источник)
      print('ПРОВЕРКА РОЛИ: Запрашиваем данные из Firestore...');
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
          
      print('ПРОВЕРКА РОЛИ: Документ существует: ${userDoc.exists}');
      
      if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData != null) {
          print('ПРОВЕРКА РОЛИ: Данные документа: $userData');
          
          // Проверяем поле role
          if (userData.containsKey('role')) {
            String firestoreRole = userData['role'].toString();
            print('ПРОВЕРКА РОЛИ: Роль из Firestore: "$firestoreRole"');
            
            // Обрезаем пробелы и приводим к нижнему регистру для надежного сравнения
            firestoreRole = firestoreRole.trim().toLowerCase();
            
            // Обновляем кэшированную роль
            await _saveUserRole(firestoreRole);
            
            // Явное сравнение строк с выводом отладочной информации
            final isEng = firestoreRole == 'engineer'.toLowerCase();
            print('ПРОВЕРКА РОЛИ: Сравнение: "$firestoreRole" == "engineer" = $isEng');
            print('================================================================');
            return isEng;
          } else {
            print('ПРОВЕРКА РОЛИ: Поле role отсутствует в документе');
          }
        } else {
          print('ПРОВЕРКА РОЛИ: Данные документа пустые');
        }
      } else {
        print('ПРОВЕРКА РОЛИ: Документ пользователя не найден в Firestore');
      }
      
      // Если не нашли информацию в Firestore, проверяем кэшированную роль
      final cachedRole = await getUserRole();
      print('ПРОВЕРКА РОЛИ: Кэшированная роль: "$cachedRole"');
      
      // Явное сравнение строк с выводом отладочной информации
      final cachedRoleTrimmed = cachedRole?.trim().toLowerCase() ?? "";
      final isEngFromCache = cachedRoleTrimmed == 'engineer'.toLowerCase();
      print('ПРОВЕРКА РОЛИ: Сравнение (кэш): "$cachedRoleTrimmed" == "engineer" = $isEngFromCache');
      print('================================================================');
      
      return isEngFromCache;
    } catch (e) {
      print('ПРОВЕРКА РОЛИ: Ошибка при проверке: $e');
      
      // В случае ошибки, возвращаемся к кэшированной роли
      final cachedRole = await getUserRole();
      final cachedRoleTrimmed = cachedRole?.trim().toLowerCase() ?? "";
      final isEngFromCache = cachedRoleTrimmed == 'engineer'.toLowerCase();
      print('ПРОВЕРКА РОЛИ: Резервный результат: $isEngFromCache');
      print('================================================================');
      return isEngFromCache;
    }
  }
  
  // Аутентификация пользователя
  Future<bool> signIn(String email, String password) async {
    print('Попытка входа: $email');
    
    try {
      // Для тестирования разрешаем вход с тестовыми данными вне Firebase
      if (email == 'engineer@test.com' && password == 'engineer123') {
        print('Используем тестовые данные инженера');
        await _saveUserRole('engineer');
        return true;
      }
      
      if (email == 'test@example.com' && password == 'password') {
        print('Используем тестовые данные обычного пользователя');
        await _saveUserRole('user');
        return true;
      }
      
      // Пробуем войти через Firebase
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Если пользователь успешно вошел
      if (result.user != null) {
        print('Успешный вход через Firebase: ${result.user!.email}');
        
        // Получаем роль из Firestore
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(result.user!.uid)
            .get();
        
        String role = 'user'; // По умолчанию
        
        if (userDoc.exists) {
          final userData = userDoc.data();
          if (userData != null && userData.containsKey('role')) {
            role = userData['role'];
            print('Получена роль из Firestore: $role');
          }
        } else {
          // Если документа нет, проверяем email
          if (result.user!.email?.endsWith('@engineer.hydrant.ru') == true) {
            print('Обнаружен email инженера');
            role = 'engineer';
          }
          
          // Создаем документ пользователя с нужной ролью
          await FirebaseFirestore.instance
              .collection('users')
              .doc(result.user!.uid)
              .set({
                'uid': result.user!.uid,
                'email': result.user!.email,
                'role': role,
                'name': 'Пользователь',
                'createdAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
        }
        
        // Сохраняем роль в SharedPreferences
        await _saveUserRole(role);
        return true;
      }
      return false;
    } catch (e) {
      print('Ошибка при входе: $e');
      return false;
    }
  }
  
  // Регистрация пользователя
  Future<bool> register(String email, String password) async {
    try {
      // Создаем учетную запись в Firebase Auth
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      if (result.user != null) {
        // При регистрации всегда назначаем роль "user"
        await _saveUserRole('user');
        
        // Создаем документ в Firestore с uid пользователя из Firebase Auth
        await FirebaseFirestore.instance
            .collection('users')
            .doc(result.user!.uid)
            .set({
              'uid': result.user!.uid,
              'email': email,
              'role': 'user',
              'name': 'Пользователь',
              'createdAt': FieldValue.serverTimestamp(),
            });
        
        print('Пользователь успешно зарегистрирован и создан в Firestore: ${result.user!.uid}');
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
      _currentSessionRole = null;
      final prefs = await _prefs;
      await prefs.remove(_userRoleKey);
      print('Выход выполнен успешно, роль сброшена');
    } catch (e) {
      print('Ошибка при выходе: $e');
    }
  }
  
  // Проверка авторизации
  Future<bool> isLoggedIn() async {
    return _auth.currentUser != null;
  }
} 