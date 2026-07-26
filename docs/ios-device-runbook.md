# iOS 실기기 실행 가이드

이 문서는 `Song Junsun's iPhone`에서 Flutter 앱을 실행할 때 필요한 설정과, 이번에 발생한 오류를 순서대로 해결하는 방법을 정리한다.

## 1. 먼저 확인할 상태

프로젝트는 반드시 Git 원본에서 받은 완전한 폴더여야 한다. `ios/Runner.xcodeproj`가 없으면 CocoaPods와 Xcode는 실행할 수 없다.

```bash
cd /Users/evan/Desktop/02_project_dev/dev/campon
ls -ld ios/Runner.xcodeproj ios/Runner.xcworkspace
```

두 경로가 모두 출력되면 다음 단계로 진행한다. 하나라도 없으면 iOS 폴더를 임의로 복사하지 말고 팀의 Git 원본을 다시 받아야 한다. 원본이 전혀 없을 때만 아래처럼 iOS 프로젝트를 재생성한다.

```bash
mv ios ios.backup
flutter create --platforms=ios .
flutter pub get
cd ios
pod install
cd ..
```

재생성 후에는 3절의 로그인 설정과 4절의 서명 설정을 반드시 다시 적용해야 한다.

## 2. 소스 위치와 macOS 확장 속성

> **2026-07-12 확정된 근본 원인:** 이 프로젝트 폴더는 iCloud File Provider가 관리한다
> (`com.apple.fileprovider.fpfs#P` 확인). 프로젝트 안에 새로 생성되는 `.framework`
> 디렉터리에는 수 초 안에 `com.apple.FinderInfo`가 자동으로 붙고, codesign이 이를
> 거부해 빌드가 실패한다. `tmp_build`를 `/private/tmp/campon_flutter_build`로 향하는
> 심링크로 두면 산출물이 동기화 영역 밖에 생성되어 문제가 발생하지 않는다.
> **주의: `flutter clean`은 이 심링크를 삭제한다.** clean 후에는 반드시
> `scripts/bootstrap.sh`를 실행해 심링크를 복구할 것. 근본적으로는 저장소를
> iCloud 동기화 폴더 밖(예: `~/Developer`)으로 옮기는 것이 가장 안전하다.

이전 오류의 대상은 `tmp_build/ios/.../App.framework/App`이었다. 즉, 소스 전체가 아니라 이전 빌드 산출물에 Finder 정보 또는 리소스 포크가 남아 코드서명이 거부된 경우다.

현재 생성한 `Runner.app`에는 `com.apple.provenance` 속성이 있어도 ad-hoc 코드서명에 성공했다. `com.apple.provenance`만으로는 이 오류의 원인이 아니다. 먼저 재생성 가능한 산출물만 지우고 다시 빌드한다.

```bash
rm -rf tmp_build build
flutter clean
flutter pub get
cd ios
pod install
cd ..
flutter build ios --debug
```

같은 오류가 다시 나오면 실패 경로의 실제 속성을 확인한다.

```bash
xattr -lr tmp_build | rg 'com\.apple\.(FinderInfo|ResourceFork)'
```

`FinderInfo` 또는 `ResourceFork`가 다시 나타나면, 기존 폴더를 `mv`하지 말고 Git 원본을 iCloud/Desktop 밖의 새 경로에 clone한다. `mv`는 확장 속성을 그대로 보존한다.

```bash
cd "$HOME/Developer"
git clone <TEAM_REPOSITORY_URL> campon
cd campon
flutter pub get
cd ios
pod install
cd ..
```

`Pods`, `build`, `tmp_build`는 생성물이다. 소유권 또는 확장 속성이 꼬였을 때 원본 소스 파일을 수정하기보다 이 폴더들을 재생성하는 편이 안전하다.

## 3. 로그인 SDK iOS 설정

현재 프로젝트는 아래 설정을 복구했다.

| 항목 | 현재 프로젝트 값 | 목적 |
| --- | --- | --- |
| iOS Bundle ID | `com.seohamin.camping` | Apple App ID와 일치해야 한다. |
| Apple Team ID | `Q5U58YNG6X` | 백업에서 복구한 값이다. 실제 App ID 소유 Team ID와 일치하는지 관리자 확인이 필요하다. |
| Apple entitlement | `com.apple.developer.applesignin` | Sign in with Apple에 필요하다. |
| Kakao URL Scheme | `kakao735b945f18caa332a29deddf87c80bb8` | Kakao 앱 로그인 콜백에 필요하다. |
| Google URL Scheme | `com.googleusercontent.apps.203621955396-i15e9g0rirjpd55ju9fn6av6v9s672v3` | Google 로그인 콜백에 필요하다. |

로그인 SDK/백엔드 담당자는 다음 정보를 프론트 담당자에게 제공해야 한다.

| 정보 | 설정 위치 |
| --- | --- |
| Apple Developer Team 접근 권한 | Apple Developer 웹사이트의 People |
| Apple App ID, Service ID, Redirect URI | Apple Developer 및 백엔드 OAuth 설정 |
| Google iOS OAuth Client ID, server client ID | Google Cloud Console 및 Dart 실행 옵션 |
| Kakao Native App Key, REST/백엔드 교환 경로 | Kakao Developers 및 Dart 실행 옵션 |

`APPLE_REDIRECT_URI`와 `KAKAO_BACKEND_AUTH_PATH`는 현재 코드에 기본값이 없다. SDK/백엔드 담당자가 값을 제공해야 로그인 후 서버 토큰 교환이 가능하다.

실행 시 필요한 Dart define 예시는 다음과 같다. 실제 값은 팀의 비밀 관리 방식으로 전달받는다.

```bash
flutter run -d 00008140-001129043A3B801C \
  --dart-define=KAKAO_BACKEND_AUTH_PATH=/api/v1/auth/oauth2/kakao \
  --dart-define=APPLE_REDIRECT_URI=https://example.com/auth/apple/callback
```

## 4. Apple Developer 팀과 코드서명

최신 검증에서 `flutter build ios --debug`는 다음 세 오류로 실패했다.

```text
Failed Registering Bundle Identifier: com.seohamin.camping
Provisioning profile "iOS Team Provisioning Profile: *" doesn't support the Sign in with Apple capability.
Provisioning profile ... doesn't include the com.apple.developer.applesignin entitlement.
```

따라서 현재 Xcode에 설정된 Team `Q5U58YNG6X`는 `com.seohamin.camping`을 등록하거나 사용할 권한이 없다. 이는 프론트 코드 오류가 아니다. 로그인 SDK를 만든 개발자에게 "이 Bundle ID를 실제로 소유한 Apple Developer Team ID"를 확인해야 한다.

팀의 Account Holder 또는 Admin이 처리한다.

1. `developer.apple.com/account`에 로그인한다.
2. `People`에서 프론트 개발자의 Apple ID를 초대한다.
3. `Certificates, Identifiers & Profiles` 접근 권한을 부여한다.
4. 프론트 개발자가 초대 메일을 수락한다.
5. `Identifiers`에서 `com.seohamin.camping`을 열고 `Sign in with Apple`을 활성화한다.
6. 이 명시적 App ID의 Development Provisioning Profile을 새로 생성하거나 갱신한다. `iOS Team Provisioning Profile: *` 같은 와일드카드 프로파일은 사용하지 않는다.
7. 프론트 개발자는 Xcode `Settings > Accounts`에서 Apple ID를 다시 로그인해 새 Team이 목록에 보이는지 확인한다.

프론트 개발자는 Xcode에서 `ios/Runner.xcworkspace`를 열고 `Runner > Signing & Capabilities`를 다음과 같이 맞춘다.

| 설정 | 값 |
| --- | --- |
| Team | `com.seohamin.camping`을 실제로 소유한 팀 |
| Bundle Identifier | `com.seohamin.camping` |
| Automatically manage signing | 켬 |
| Capability | Sign in with Apple |

운영 App ID의 팀 권한을 받을 수 없다면 개발용 Bundle ID를 별도로 만들어야 한다. 예를 들어 `com.seohamin.camping.dev.<개발자식별자>`를 Apple Developer에 등록하고 Sign in with Apple을 활성화한다. 이 선택은 Apple, Google, Kakao, 백엔드의 앱 식별자와 Redirect URI도 모두 개발용으로 추가해야 하므로, 운영 ID를 단순히 로컬에서 바꾸는 방식으로 해결하면 안 된다.

## 5. macOS와 iPhone 실행 권한

`Failed to get target destination: AppleEvent handler failed`는 Flutter가 Xcode를 자동 제어하지 못했을 때 발생한다.

1. macOS `시스템 설정 > 개인정보 보호 및 보안 > 자동화`를 연다.
2. `flutter run`을 실행한 앱(Terminal, iTerm, Warp 또는 VS Code) 아래의 `Xcode` 권한을 켠다.
3. iPhone 잠금을 해제하고 Mac 신뢰를 허용한다.
4. iPhone의 `설정 > 개인정보 보호 및 보안 > 개발자 모드`를 켠다.
5. Xcode에서 한 번 직접 실행한다.

```bash
open ios/Runner.xcworkspace
```

Xcode 상단에서 `Song Junsun's iPhone`을 선택하고 `Product > Run`을 실행한다. 성공 후 터미널에서 다시 실행한다.

```bash
flutter run -d 00008140-001129043A3B801C
```

## 6. 빌드 순서

모든 권한과 설정이 끝난 뒤 아래 순서만 실행한다.

```bash
flutter clean
flutter pub get
cd ios
pod install
cd ..
flutter run -d 00008140-001129043A3B801C
```

## 7. 오류별 즉시 조치

| 오류 문구 | 원인 | 조치 |
| --- | --- | --- |
| `Unable to find ... Runner.xcodeproj` | iOS 프로젝트 파일 누락 | 1절의 Git 복구 또는 iOS 재생성 |
| `CompileAssetCatalogVariant failed` | 아이콘 또는 에셋 카탈로그 문제 | `ios/Runner/Assets.xcassets/AppIcon.appiconset`을 확인하고 `flutter clean` 후 재빌드 |
| `resource fork ... not allowed` | 이전 생성물의 Finder 정보 또는 리소스 포크 | `tmp_build`와 `build` 삭제 후 재생성, 계속되면 새 Git clone |
| `Failed Registering Bundle Identifier` | 다른 Apple Developer Team의 App ID | 4절의 팀 초대 및 올바른 Bundle ID 선택 |
| `doesn't support Sign in with Apple` | 와일드카드 프로파일 또는 capability 누락 | 명시적 App ID에 capability 활성화, 프로파일 갱신 |
| `AppleEvent handler failed` | macOS Xcode 자동화 권한 누락 | 5절의 Automation 권한 허용 |
| `Error connecting to the service protocol` | 앱이 기동 직후 종료되었거나 Xcode 연결이 실패 | 먼저 Xcode에서 직접 실행하고, 앱 로그의 첫 Dart/Native 예외를 확인 |

## 8. 이번 작업의 검증 범위

이 프로젝트에서 다음은 확인됐다.

- `ios/Runner.xcodeproj`와 `ios/Runner.xcworkspace`가 존재한다.
- `pod install`이 완료된 상태다.
- 코드서명을 끈 Xcode device build에서 `Runner.app`과 `Assets.car`가 생성됐다.
- Flutter 정적 분석은 오류 없이 완료됐다.
- 생성된 `Runner.app`의 ad-hoc 코드서명이 성공했다.
- 실제 Apple 개발용 서명은 App ID 소유 Team 권한과 프로비저닝 프로파일 부족으로 실패했다.

실제 기기 설치는 Apple Developer 팀 초대, 프로비저닝 프로파일, macOS Automation 권한처럼 로컬 코드 밖의 권한이 충족된 뒤에 검증해야 한다.
