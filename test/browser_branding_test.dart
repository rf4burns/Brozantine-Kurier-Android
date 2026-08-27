import 'package:flutter_test/flutter_test.dart';
import 'package:kurier_web/app/browser_branding.dart';

void main() {
  test('browser tab title uses server name then Kurier', () {
    expect(browserTabTitle(), 'Kurier');
    expect(browserTabTitle(infoName: 'Kurier'), 'Kurier');
    expect(
      browserTabTitle(infoName: 'Holy Broman Empire'),
      'Holy Broman Empire - Kurier',
    );
    expect(
      browserTabTitle(serverName: 'Test Server', infoName: 'Old Name'),
      'Test Server - Kurier',
    );
  });

  test('browser tab icon prefers the server logo', () {
    expect(browserTabIconUrl(), isNull);
    expect(
      browserTabIconUrl(origin: 'https://sharkord.brozantine.com'),
      'https://sharkord.brozantine.com/favicon.ico',
    );
    expect(
      browserTabIconUrl(
        logoUrl: 'https://host/public/hbe.png',
        origin: 'https://host',
      ),
      'https://host/public/hbe.png',
    );
  });
}
