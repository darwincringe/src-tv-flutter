/// Whether an account may play and add titles to the library.
///
/// `admin == 1` is unrestricted. Premium with a null or blank expiry never
/// expires. A premium flag whose expiry is in the past does not count.
bool canAccessStreams({
  required int admin,
  required int premium,
  String? premiumExpiresAt,
  DateTime? now,
}) {
  if (admin == 1) return true;
  if (premium != 1) return false;
  final raw = premiumExpiresAt?.trim();
  if (raw == null || raw.isEmpty) return true;
  final exp = DateTime.tryParse(raw);
  if (exp == null) return false;
  return exp.isAfter(now ?? DateTime.now());
}
