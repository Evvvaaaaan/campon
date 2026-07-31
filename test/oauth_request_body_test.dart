import 'package:campon/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthProvider.authRequestBody', () {
    test('Kakao는 서버가 요구하는 accessToken 필드로 자격 증명을 보낸다', () {
      expect(
        AuthProvider.kakao.authRequestBody(
          credential: 'kakao-access-token',
          name: 'Kakao User',
        ),
        <String, String>{
          'accessToken': 'kakao-access-token',
          'name': 'Kakao User',
        },
      );
    });

    test('Google은 authorization code를 code 필드로 보낸다', () {
      expect(
        AuthProvider.google.authRequestBody(
          credential: 'google-server-auth-code',
          name: 'Google User',
        ),
        <String, String>{
          'code': 'google-server-auth-code',
          'name': 'Google User',
        },
      );
    });

    test('Apple은 authorization code를 code 필드로 보낸다', () {
      expect(
        AuthProvider.apple.authRequestBody(
          credential: 'apple-authorization-code',
          name: 'Apple User',
        ),
        <String, String>{
          'code': 'apple-authorization-code',
          'name': 'Apple User',
        },
      );
    });
  });
}
