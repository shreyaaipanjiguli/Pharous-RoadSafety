class CommunityReport {
  final int id;
  final int userId;
  final String type;
  final int severity;
  final String? description;
  final double latitude;
  final double longitude;
  final String status;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final int confirmVotes;
  final int clearVotes;

  CommunityReport({
    required this.id,
    required this.userId,
    required this.type,
    required this.severity,
    this.description,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.createdAt,
    this.expiresAt,
    required this.confirmVotes,
    required this.clearVotes,
  });

  factory CommunityReport.fromJson(Map<String, dynamic> json) {
    return CommunityReport(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      type: json['type'] as String,
      severity: json['severity'] as int,
      description: json['description'] as String?,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at'] as String),
      confirmVotes: json['confirm_votes'] as int? ?? 0,
      clearVotes: json['clear_votes'] as int? ?? 0,
    );
  }
}
