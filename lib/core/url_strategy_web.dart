import 'package:flutter_web_plugins/url_strategy.dart';

/// Clean path URLs (no `/#/`) on web. Safe because the server serves
/// index.html for unknown paths (nginx `try_files … /index.html`), so a shared
/// deep link or a refresh still boots the SPA and go_router parses the path.
void configureUrlStrategy() => usePathUrlStrategy();
