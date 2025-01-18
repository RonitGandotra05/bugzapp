class ApiConstants {
  static String get baseUrl => 'https://bugapi.tripxap.com';
  static String get wsUrl => baseUrl.replaceFirst('https://', 'wss://');
  static const String loginEndpoint = '/login';
  static const String usersEndpoint = '/users';
  static const String bugReportsEndpoint = '/bug_reports';
  static const String projectsEndpoint = '/projects';
  static const String uploadEndpoint = '/upload';
  static const String allUsersEndpoint = '/all_users';
} 