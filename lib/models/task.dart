import 'package:cloud_firestore/cloud_firestore.dart';

class Task {
  final String id;
  final String title;
  final String description;
  final String address;
  final String status;
  final String assignedTo;
  final String assignedToName;
  final GeoPoint? coordinates;
  final String arrivalCode;
  final String completionCode;
  final double price;
  final String currency;
  final String paymentMethod;
  final String paymentStatus;
  final String userId;
  final String userName;
  final String userEmail;
  final String userPhone;
  final String additionalInfo;
  final DateTime createdAt;
  final DateTime? paidAt;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.address,
    required this.status,
    required this.assignedTo,
    required this.assignedToName,
    this.coordinates,
    required this.arrivalCode,
    required this.completionCode,
    required this.price,
    required this.currency,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.userPhone,
    required this.additionalInfo,
    required this.createdAt,
    this.paidAt,
  });

  factory Task.fromFirestore(dynamic doc) {
    try {
      if (doc == null) {
        print('ОШИБКА: Task.fromFirestore получил null документ');
        throw Exception('Документ равен null');
      }
      
      final dynamic rawData = doc.data();
      if (rawData == null) {
        print('ОШИБКА: Task.fromFirestore получил документ с пустыми данными');
        throw Exception('Данные документа равны null');
      }
      
      final Map<String, dynamic> data = Map<String, dynamic>.from(rawData);
      
      print('===== ПРОВЕРКА КОНВЕРТАЦИИ TASK =====');
      print('Документ ID: ${doc.id}');
      print('- assignedTo: "${data['assignedTo'] ?? 'не указан'}"');
      print('- assignedToName: "${data['assignedToName'] ?? 'не указан'}"');
      print('- status: "${data['status'] ?? 'не указан'}"');
      print('- Все поля:');
      data.forEach((key, value) {
        print('  - $key: $value');
      });
      
      final String id = doc.id ?? '';
      final String title = data['title'] as String? ?? '';
      final String description = data['description'] as String? ?? '';
      final String address = data['address'] as String? ?? '';
      final String status = data['status'] as String? ?? '';
      final String assignedTo = data['assignedTo'] as String? ?? '';
      final String assignedToName = data['assignedToName'] as String? ?? '';
      final GeoPoint? coordinates = data['coordinates'] as GeoPoint?;
      final String arrivalCode = data['arrivalCode'] as String? ?? '';
      final String completionCode = data['completionCode'] as String? ?? '';
      
      double price = 0.0;
      if (data['price'] != null) {
        if (data['price'] is double) {
          price = data['price'] as double;
        } else if (data['price'] is int) {
          price = (data['price'] as int).toDouble();
        } else {
          try {
            price = double.parse(data['price'].toString());
          } catch (e) {
            print('Ошибка при преобразовании цены: ${data['price']}');
          }
        }
      }
      
      final String currency = data['currency'] as String? ?? '₽';
      final String paymentMethod = data['paymentMethod'] as String? ?? '';
      final String paymentStatus = data['paymentStatus'] as String? ?? '';
      final String userId = data['userId'] as String? ?? '';
      final String userName = data['userName'] as String? ?? '';
      final String userEmail = data['userEmail'] as String? ?? '';
      final String userPhone = data['userPhone'] as String? ?? '';
      final String additionalInfo = data['additionalInfo'] as String? ?? '';
      
      DateTime createdAt = DateTime.now();
      if (data['createdAt'] != null && data['createdAt'] is Timestamp) {
        createdAt = (data['createdAt'] as Timestamp).toDate();
      }
      
      DateTime? paidAt;
      if (data['paidAt'] != null && data['paidAt'] is Timestamp) {
        paidAt = (data['paidAt'] as Timestamp).toDate();
      }
      
      return Task(
        id: id,
        title: title,
        description: description,
        address: address,
        status: status,
        assignedTo: assignedTo,
        assignedToName: assignedToName,
        coordinates: coordinates,
        arrivalCode: arrivalCode,
        completionCode: completionCode,
        price: price,
        currency: currency,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        userId: userId,
        userName: userName,
        userEmail: userEmail,
        userPhone: userPhone,
        additionalInfo: additionalInfo,
        createdAt: createdAt,
        paidAt: paidAt,
      );
    } catch (e) {
      print('Ошибка при парсинге Task из Firestore: $e');
      print(StackTrace.current);
      return Task(
        id: 'error',
        title: 'Ошибка загрузки',
        description: 'Не удалось загрузить данные заказа',
        address: '',
        status: '',
        assignedTo: '',
        assignedToName: '',
        coordinates: null,
        arrivalCode: '',
        completionCode: '',
        price: 0,
        currency: '₽',
        paymentMethod: '',
        paymentStatus: '',
        userId: '',
        userName: '',
        userEmail: '',
        userPhone: '',
        additionalInfo: '',
        createdAt: DateTime.now(),
        paidAt: null,
      );
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'address': address,
      'status': status,
      'assignedTo': assignedTo,
      'assignedToName': assignedToName,
      'coordinates': coordinates,
      'arrivalCode': arrivalCode,
      'completionCode': completionCode,
      'price': price,
      'currency': currency,
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'userPhone': userPhone,
      'additionalInfo': additionalInfo,
      'createdAt': Timestamp.fromDate(createdAt),
      'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
    };
  }
} 