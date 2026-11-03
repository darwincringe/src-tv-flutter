import 'package:flutter_test/flutter_test.dart';
import 'package:srctv_flutter/data/auth/premium_access.dart';

void main() {
  final now = DateTime.utc(2026, 11, 1, 6);

  test('admin can watch with premium off or expired', () {
    expect(
      canAccessStreams(admin: 1, premium: 0, premiumExpiresAt: null, now: now),
      isTrue,
    );
    expect(
      canAccessStreams(
        admin: 1,
        premium: 1,
        premiumExpiresAt: '2020-01-01T00:00:00.000Z',
        now: now,
      ),
      isTrue,
    );
  });

  test('premium with no expiry never expires', () {
    expect(
      canAccessStreams(admin: 0, premium: 1, premiumExpiresAt: null, now: now),
      isTrue,
    );
    expect(
      canAccessStreams(admin: 0, premium: 1, premiumExpiresAt: '  ', now: now),
      isTrue,
    );
  });

  test('premium is refused once expires_at is in the past', () {
    expect(
      canAccessStreams(
        admin: 0,
        premium: 1,
        premiumExpiresAt: '2026-10-31T00:00:00.000Z',
        now: now,
      ),
      isFalse,
    );
    expect(
      canAccessStreams(
        admin: 0,
        premium: 1,
        premiumExpiresAt: '2026-12-01T00:00:00.000Z',
        now: now,
      ),
      isTrue,
    );
  });

  test('a non-premium account cannot watch', () {
    expect(
      canAccessStreams(admin: 0, premium: 0, premiumExpiresAt: null, now: now),
      isFalse,
    );
    expect(
      canAccessStreams(
        admin: 0,
        premium: 1,
        premiumExpiresAt: 'not-a-date',
        now: now,
      ),
      isFalse,
    );
  });
}
