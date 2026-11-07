import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation.dart';
import '../../core/theme.dart';

/// Public privacy policy. [korean] selects the Korean page at `/privacy/ko`.
/// The English page is `/privacy`. Sections follow the items Samsung's TV
/// seller guide expects a privacy policy to cover.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key, this.korean = false});

  final bool korean;

  @override
  Widget build(BuildContext context) {
    final copy = korean ? _korean : _english;
    return Scaffold(
      backgroundColor: AppColors.charcoal,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: korean ? '뒤로' : 'Back',
                      onPressed: () => navBack(context),
                      icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => context.go(korean ? '/privacy' : '/privacy/ko'),
                      child: Text(korean ? 'English' : '한국어'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  copy.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  copy.effective,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 20),
                Text(
                  copy.intro,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                for (final section in copy.sections) ...[
                  const SizedBox(height: 28),
                  Text(
                    section.heading,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    section.body,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      height: 1.55,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Copy {
  const _Copy({
    required this.title,
    required this.effective,
    required this.intro,
    required this.sections,
  });

  final String title;
  final String effective;
  final String intro;
  final List<_Section> sections;
}

class _Section {
  const _Section(this.heading, this.body);
  final String heading;
  final String body;
}

const _english = _Copy(
  title: 'Privacy Policy',
  effective: 'Effective date: November 5, 2026',
  intro:
      'SRC TV (srctv.space) describes here what personal information we collect, '
      'why we use it, how long we keep it, and how you can ask us about it.',
  sections: [
    _Section(
      '1. Information we collect',
      'When you create an account we collect your username, your email address, '
      'and a password. The password is stored only as a one-way hash. We do not '
      'keep the password you typed.\n\n'
      'If you use an account, we also store the titles you save, your watch '
      'progress (the title, the season and episode when that applies, and the '
      'playback position), subtitle choices you save for a title, and whether '
      'that account is allowed to play, including the date that access ends if '
      'one is set.\n\n'
      'You can browse without an account. We do not ask for your name, phone '
      'number, postal address, or payment card.',
    ),
    _Section(
      '2. Why we use it',
      'We use this information to create your account and sign you in, to keep '
      'your library, watch progress, and subtitle choices on that account, to '
      'apply the playback access set on the account, and to answer a request '
      'you send us about this policy.\n\n'
      'We do not use this information for advertising, and we do not sell it.',
    ),
    _Section(
      '3. How long we keep it',
      'We keep account information while the account exists. Library items, '
      'watch progress, and subtitle choices stay until you remove them or the '
      'account is deleted.',
    ),
    _Section(
      '4. How we delete it',
      'When an account is deleted, we delete the username, email address, '
      'password hash, library, watch progress, and subtitle choices from our '
      'server. Information saved on your device is removed when you sign out '
      'or clear the app or site data.',
    ),
    _Section(
      '5. Sharing with others',
      'We do not sell personal information, and we do not give it to other '
      'companies for their own marketing.\n\n'
      'Playing a trailer opens that video on YouTube. YouTube then handles the '
      'playback under its own policy. We do not send your email address or '
      'password to YouTube.\n\n'
      'Titles, images, and descriptions come from The Movie Database. Those '
      'requests do not include your email address.',
    ),
    _Section(
      '6. Processing for us',
      'Account information is stored on the servers that operate srctv.space '
      'and api.srctv.space. Those servers may be outside your country. We do '
      'not hire another company to use your personal information for '
      'advertising or analytics.',
    ),
    _Section(
      '7. Your rights',
      'You can ask us what account information we have, ask us to correct your '
      'email address or username, and ask us to delete the account and the '
      'information listed above.\n\n'
      'Email the address at the end of this page from the email address on the '
      'account. We may need to confirm that the request is yours.\n\n'
      'You can refuse to create an account. Browsing still works. An account '
      'is required for library sync and for playback that the account is '
      'allowed to open.',
    ),
    _Section(
      '8. How we protect it',
      'We send account information over HTTPS. Passwords are stored as hashes. '
      'Access to the account database is limited to operating the service. No '
      'method of storage or transmission is completely secure.',
    ),
    _Section(
      '9. Information stored on your device',
      'The app stores the sign-in session, email address, username, library, '
      'and watch progress on the device so you stay signed in. This is local '
      'storage on the device. It is not an advertising cookie. You can remove '
      'it by signing out or by clearing the site data in the browser or on the TV.',
    ),
    _Section(
      '10. Children',
      'SRC TV is not directed at children under 14. We do not knowingly collect '
      'personal information from a child under 14. If you believe a child has '
      'given us an email address, contact us and we will delete that account.',
    ),
    _Section(
      '11. Changes',
      'If this policy changes, we will update this page and the effective date '
      'at the top.',
    ),
    _Section(
      '12. Contact',
      'Privacy requests: privacy@srctv.space\n'
      'Service: https://srctv.space',
    ),
  ],
);

const _korean = _Copy(
  title: '개인정보 처리방침',
  effective: '시행일: 2026년 11월 5일',
  intro:
      'SRC TV(srctv.space)는 어떤 개인정보를 수집하고, 왜 이용하며, 얼마나 보관하고, '
      '어떻게 열람·정정·삭제를 요청할 수 있는지 이 방침에서 알립니다.',
  sections: [
    _Section(
      '1. 수집하는 개인정보',
      '계정을 만들 때 아이디, 이메일 주소, 비밀번호를 수집합니다. 비밀번호는 '
      '일방향 해시로만 저장하며, 입력한 비밀번호 원문은 보관하지 않습니다.\n\n'
      '계정을 이용하면 저장한 작품, 시청 기록(작품, 해당하는 경우 시즌과 회차, '
      '재생 위치), 작품별로 저장한 자막 선택, 그리고 해당 계정의 재생 허용 여부와 '
      '이용 종료일이 설정된 경우 그 날짜를 함께 보관합니다.\n\n'
      '계정 없이 둘러볼 수 있습니다. 이름, 전화번호, 주소, 결제 카드 정보는 '
      '받지 않습니다.',
    ),
    _Section(
      '2. 이용 목적',
      '계정 생성과 로그인, 보관함·시청 기록·자막 선택을 그 계정에 유지하는 일, '
      '계정에 설정된 재생 권한을 적용하는 일, 그리고 이 방침에 대한 문의에 '
      '답하는 일에 사용합니다.\n\n'
      '광고에 사용하지 않으며, 판매하지 않습니다.',
    ),
    _Section(
      '3. 보유 기간',
      '계정 정보는 계정이 있는 동안 보관합니다. 보관함, 시청 기록, 자막 선택은 '
      '이용자가 지우거나 계정이 삭제될 때까지 보관합니다.',
    ),
    _Section(
      '4. 파기',
      '계정을 삭제하면 서버에서 아이디, 이메일 주소, 비밀번호 해시, 보관함, '
      '시청 기록, 자막 선택을 삭제합니다. 기기에 남은 정보는 로그아웃하거나 '
      '앱 또는 사이트 데이터를 지우면 삭제됩니다.',
    ),
    _Section(
      '5. 제3자 제공',
      '개인정보를 판매하지 않으며, 다른 회사의 마케팅을 위해 제공하지 않습니다.\n\n'
      '예고편을 재생하면 해당 영상이 YouTube에서 열립니다. 재생은 YouTube의 '
      '정책에 따릅니다. 이메일 주소와 비밀번호는 YouTube에 보내지 않습니다.\n\n'
      '작품 제목, 이미지, 소개는 The Movie Database에서 가져옵니다. 이 요청에는 '
      '이메일 주소가 포함되지 않습니다.',
    ),
    _Section(
      '6. 처리 위탁과 국외 보관',
      '계정 정보는 srctv.space와 api.srctv.space를 운영하는 서버에 저장됩니다. '
      '이 서버는 이용자의 국가 밖에 있을 수 있습니다. 광고나 분석을 위해 다른 '
      '회사에 개인정보 처리를 맡기지 않습니다.',
    ),
    _Section(
      '7. 이용자의 권리',
      '계정 정보의 열람, 이메일 주소나 아이디의 정정, 계정과 위에 적힌 정보의 '
      '삭제를 요청할 수 있습니다.\n\n'
      '계정에 등록된 이메일 주소로 이 페이지 하단의 주소에 보내 주세요. 요청한 '
      '사람이 계정 본인인지 확인할 수 있습니다.\n\n'
      '계정 생성을 거부할 수 있습니다. 둘러보기는 그대로 이용할 수 있습니다. '
      '보관함 동기화와, 계정에 허용된 재생에는 계정이 필요합니다.',
    ),
    _Section(
      '8. 안전성 확보 조치',
      '계정 정보는 HTTPS로 전송합니다. 비밀번호는 해시로 저장합니다. 계정 '
      '데이터베이스 접근은 서비스 운영에 필요한 범위로 제한합니다. 어떤 저장이나 '
      '전송 방법도 완전히 안전하지는 않습니다.',
    ),
    _Section(
      '9. 기기에 저장되는 정보',
      '로그인 상태를 유지하기 위해 로그인 세션, 이메일 주소, 아이디, 보관함, '
      '시청 기록을 기기에 저장합니다. 이것은 기기의 로컬 저장이며 광고 쿠키가 '
      '아닙니다. 로그아웃하거나 브라우저 또는 TV에서 사이트 데이터를 지우면 '
      '삭제할 수 있습니다.',
    ),
    _Section(
      '10. 만 14세 미만 아동',
      'SRC TV는 만 14세 미만 아동을 대상으로 하지 않으며, 아동의 개인정보를 '
      '고의로 수집하지 않습니다. 아동이 이메일 주소를 제공했다고 생각되면 '
      '연락해 주세요. 해당 계정을 삭제합니다.',
    ),
    _Section(
      '11. 방침의 변경',
      '이 방침이 바뀌면 이 페이지와 상단의 시행일을 갱신합니다.',
    ),
    _Section(
      '12. 연락처',
      '개인정보 문의: privacy@srctv.space\n'
      '서비스: https://srctv.space\n'
      '개인정보 보호책임자: SRC TV 운영자 (privacy@srctv.space)',
    ),
  ],
);
