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
      final data = doc.data() as Map<String, dynamic>;
      
      print('===== ПРОВЕРКА КОНВЕРТАЦИИ TASK =====');
      print('Документ ID: ${doc.id}');
      print('- assignedTo: "${data['assignedTo']}"');
      print('- assignedToName: "${data['assignedToName']}"');
      print('- status: "${data['status']}"');
      print('- Все поля:');
      data.forEach((key, value) {
        print('  - $key: $value');
      });
      
      return Task(
        id: doc.id,
        title: data['title'] ?? '',
        description: data['description'] ?? '',
        address: data['address'] ?? '',
        status: data['status'] ?? '',
        assignedTo: data['assignedTo'] ?? '',
        assignedToName: data['assignedToName'] ?? '',
        coordinates: data['coordinates'] as GeoPoint?,
        arrivalCode: data['arrivalCode'] ?? '',
        completionCode: data['completionCode'] ?? '',
        price: (data['price'] ?? 0).toDouble(),
        currency: data['currency'] ?? '₽',
        paymentMethod: data['paymentMethod'] ?? '',
        paymentStatus: data['paymentStatus'] ?? '',
        userId: data['userId'] ?? '',
        userName: data['userName'] ?? '',
        userEmail: data['userEmail'] ?? '',
        userPhone: data['userPhone'] ?? '',
        additionalInfo: data['additionalInfo'] ?? '',
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        paidAt: (data['paidAt'] as Timestamp?)?.toDate(),
      );
    } catch (e) {
      print('Ошибка при парсинге Task из Firestore: $e');
      throw e;
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