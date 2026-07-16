import 'questionnaire_instance.dart';

class EligibleContact {
  const EligibleContact({
    required this.id,
    required this.name,
    required this.isPrimary,
    required this.canLogin,
  });

  final int id;
  final String name;
  final bool isPrimary;
  final bool canLogin;

  factory EligibleContact.fromJson(Map<String, dynamic> json) =>
      EligibleContact(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        isPrimary: (json['is_primary'] as bool?) ?? false,
        canLogin: (json['can_login'] as bool?) ?? false,
      );
}

class EligibleBooking {
  const EligibleBooking({
    required this.id,
    required this.name,
    this.date,
    required this.alreadySent,
    this.contacts = const [],
  });

  final int id;
  final String name;
  final String? date;
  final bool alreadySent;
  final List<EligibleContact> contacts;

  factory EligibleBooking.fromJson(Map<String, dynamic> json) =>
      EligibleBooking(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        date: json['date'] as String?,
        alreadySent: (json['already_sent'] as bool?) ?? false,
        contacts: (json['contacts'] as List<dynamic>? ?? [])
            .map((c) => EligibleContact.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

class AvailableQuestionnaire {
  const AvailableQuestionnaire({required this.id, required this.name});

  final int id;
  final String name;

  factory AvailableQuestionnaire.fromJson(Map<String, dynamic> json) =>
      AvailableQuestionnaire(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
      );
}

class BookingQuestionnaires {
  const BookingQuestionnaires({
    this.instances = const [],
    this.availableQuestionnaires = const [],
  });

  final List<QuestionnaireInstance> instances;
  final List<AvailableQuestionnaire> availableQuestionnaires;

  factory BookingQuestionnaires.fromJson(Map<String, dynamic> json) =>
      BookingQuestionnaires(
        instances: (json['instances'] as List<dynamic>? ?? [])
            .map((i) =>
                QuestionnaireInstance.fromJson(i as Map<String, dynamic>))
            .toList(),
        availableQuestionnaires:
            (json['available_questionnaires'] as List<dynamic>? ?? [])
                .map((q) =>
                    AvailableQuestionnaire.fromJson(q as Map<String, dynamic>))
                .toList(),
      );
}
