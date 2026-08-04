import 'dart:convert';

import 'package:campon/main.dart';
import 'package:flutter_test/flutter_test.dart';

/// 서버가 발급하는 형태의 액세스 토큰을 흉내 낸다. 서명은 검증하지 않으므로 임의 값이면 된다.
String _accessTokenWithPayload(Map<String, dynamic> payload) {
  String segment(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${segment(<String, dynamic>{'alg': 'HS256'})}'
      '.${segment(payload)}'
      '.signature';
}

void main() {
  group('userIdFromAccessToken', () {
    test('토큰 payload의 sub를 내 유저 ID로 읽는다', () {
      final token = _accessTokenWithPayload(<String, dynamic>{
        'sub': '7',
        'authorities': ['ROLE_USER'],
        'tokenType': 'access',
      });

      expect(userIdFromAccessToken(token), 7);
    });

    test('sub가 숫자 타입이어도 읽는다', () {
      final token = _accessTokenWithPayload(<String, dynamic>{'sub': 12});

      expect(userIdFromAccessToken(token), 12);
    });

    test('토큰이 없으면 null을 돌려준다', () {
      expect(userIdFromAccessToken(null), isNull);
      expect(userIdFromAccessToken(''), isNull);
    });

    test('형식이 깨진 토큰은 예외 대신 null을 돌려준다', () {
      expect(userIdFromAccessToken('not-a-jwt'), isNull);
      expect(userIdFromAccessToken('a.!!!not-base64!!!.c'), isNull);
    });

    test('sub가 숫자가 아니면 null을 돌려준다', () {
      final token = _accessTokenWithPayload(<String, dynamic>{
        'sub': 'anonymous',
      });

      expect(userIdFromAccessToken(token), isNull);
    });
  });

  group('CampPost.fromJson', () {
    test('서버가 작성자 닉네임을 주면 함께 읽는다', () {
      final post = CampPost.fromJson(<String, dynamic>{
        'id': 2,
        'campsiteId': 1,
        'authorId': 7,
        'authorNickname': '캠핑러버',
        'title': '제목',
        'content': '본문',
        'createdAt': '2026-08-04T06:14:05.568966',
      });

      expect(post.authorId, 7);
      expect(post.authorNickname, '캠핑러버');
    });

    test('작성자 닉네임이 없으면 null로 둔다', () {
      final post = CampPost.fromJson(<String, dynamic>{
        'id': 2,
        'campsiteId': 1,
        'title': '제목',
        'content': '본문',
      });

      expect(post.authorNickname, isNull);
    });
  });

  group('CampPost.metaLabel', () {
    CampPost post({String? nickname, DateTime? createdAt}) => CampPost(
      id: 1,
      campsiteId: 1,
      title: '제목',
      content: '본문',
      createdAt: createdAt,
      authorNickname: nickname,
    );

    test('작성자와 작성일이 모두 있으면 가운뎃점으로 잇는다', () {
      expect(
        post(
          nickname: '캠핑러버',
          createdAt: DateTime(2026, 8, 4, 6, 14),
        ).metaLabel,
        '캠핑러버 · 2026.08.04 06:14',
      );
    });

    test('작성자를 모르면 작성일만 보여준다', () {
      expect(
        post(createdAt: DateTime(2026, 8, 4, 6, 14)).metaLabel,
        '2026.08.04 06:14',
      );
    });

    test('작성일이 없으면 작성자만 보여준다', () {
      expect(post(nickname: '캠핑러버').metaLabel, '캠핑러버');
    });

    test('둘 다 없으면 빈 문자열이라 줄을 그리지 않는다', () {
      expect(post().metaLabel, isEmpty);
    });
  });

  group('BlockedUser.fromJson', () {
    test('서버가 닉네임을 주면 함께 읽는다', () {
      final blocked = BlockedUser.fromJson(<String, dynamic>{
        'id': 1,
        'blockedUserId': 2,
        'nickname': '캠핑러버',
        'createdAt': '2026-08-04T06:14:16.987407',
      });

      expect(blocked.blockedUserId, 2);
      expect(blocked.nickname, '캠핑러버');
    });

    test('닉네임이 없으면 유저 번호로 표시할 이름을 만든다', () {
      final blocked = BlockedUser.fromJson(<String, dynamic>{
        'id': 1,
        'blockedUserId': 2,
      });

      expect(blocked.nickname, isNull);
      expect(blocked.displayName, '유저 #2');
    });

    test('닉네임이 있으면 그것을 표시 이름으로 쓴다', () {
      final blocked = BlockedUser.fromJson(<String, dynamic>{
        'id': 1,
        'blockedUserId': 2,
        'nickname': '캠핑러버',
      });

      expect(blocked.displayName, '캠핑러버');
    });
  });

  group('postMenuActions', () {
    CampPost postBy(int? authorId) => CampPost(
      id: 1,
      campsiteId: 1,
      title: '제목',
      content: '본문',
      createdAt: null,
      authorId: authorId,
    );

    test('내가 쓴 글에는 삭제만 준다', () {
      expect(
        postMenuActions(post: postBy(7), currentUserId: 7),
        <PostAction>[PostAction.delete],
      );
    });

    test('남이 쓴 글에는 차단과 신고를 준다', () {
      expect(
        postMenuActions(post: postBy(9), currentUserId: 7),
        <PostAction>[PostAction.block, PostAction.report],
      );
    });

    test('로그인 정보를 모르면 남의 글로 취급한다', () {
      expect(
        postMenuActions(post: postBy(9), currentUserId: null),
        <PostAction>[PostAction.block, PostAction.report],
      );
    });

    test('서버가 작성자를 안 주면 삭제와 신고만 준다', () {
      // 차단할 유저 ID를 모르므로 차단은 숨기고, 기존 삭제 동작은 유지한다.
      expect(
        postMenuActions(post: postBy(null), currentUserId: 7),
        <PostAction>[PostAction.delete, PostAction.report],
      );
    });
  });
}
