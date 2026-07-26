#!/bin/sh
# flutter clean은 tmp_build 심링크를 삭제한다. 빌드 전에 이 스크립트로 복구할 것.
# 배경: 이 프로젝트는 iCloud(File Provider) 동기화 폴더 안에 있어, 프로젝트 내부에
# 생성되는 .framework 디렉터리에 com.apple.FinderInfo가 자동으로 붙고 codesign이
# "resource fork, Finder information, or similar detritus not allowed"로 실패한다.
# 빌드 산출물을 동기화 영역 밖(/private/tmp)에 두면 문제가 발생하지 않는다.
set -eu
cd "$(dirname "$0")/.."
if [ ! -L tmp_build ] || [ ! -d tmp_build ]; then
  rm -rf tmp_build
  mkdir -p /private/tmp/campon_flutter_build
  ln -s /private/tmp/campon_flutter_build tmp_build
fi
flutter pub get
