#!/usr/bin/env python3
"""CampOn 앱 아이콘을 홈 헤더 로고와 같은 디자인으로 생성한다.

1024x1024 마스터를 그린 뒤 iOS AppIcon.appiconset이 요구하는 모든 사이즈를 만든다.
좌표는 1024 기준으로 쓰고, 실제로는 4배 크기로 그린 뒤 축소해 계단 현상을 없앤다.

    python3 scripts/generate_app_icon.py

App Store 규칙상 아이콘에는 알파 채널이 없어야 하고 둥근 모서리를 직접 그리면 안 된다
(iOS가 자동으로 깎는다). 그래서 RGB 모드로 만들고 배경을 가장자리까지 채운다.
"""

from pathlib import Path

from PIL import Image, ImageDraw

# 홈 헤더의 로고 배지와 같은 색상이다.
# CampPalette.light.forest / CampPalette.dark.primary
FOREST = (30, 58, 43)
TENT = (232, 148, 74)

MASTER = 1024
SS = 4  # supersampling 배율
LAUNCH_WIDTH = 200  # 런치 마크의 1x 가로 크기(=표시 포인트)

# Contents.json이 요구하는 파일과 픽셀 크기
OUTPUTS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}


def draw_mark(draw: ImageDraw.ImageDraw) -> None:
    """홈 헤더의 Lucide tent 아이콘을 1024 기준으로 그린다."""

    def point(x: float, y: float) -> tuple[int, int]:
        # Lucide의 24x24 뷰포트를 640x640 영역으로 확대한다.
        return (round((192 + x * 640 / 24) * SS), round((192 + y * 640 / 24) * SS))

    width = 34 * SS
    # lucide-icons의 tent 경로: 두 폴, 출입구, 바닥선.
    draw.line([point(3.5, 21), point(14, 3)], fill=TENT, width=width, joint="curve")
    draw.line([point(20.5, 21), point(10, 3)], fill=TENT, width=width, joint="curve")
    draw.line([point(15.5, 21), point(12, 15), point(8.5, 21)], fill=TENT, width=width, joint="curve")
    draw.line([point(2, 21), point(22, 21)], fill=TENT, width=width)


def draw_master() -> Image.Image:
    size = MASTER * SS
    img = Image.new("RGB", (size, size), FOREST)
    draw = ImageDraw.Draw(img)
    draw_mark(draw)
    return img.resize((MASTER, MASTER), Image.LANCZOS)


def draw_launch_mark() -> Image.Image:
    """런치 스크린용 마크. 스토리보드 배경 위에 얹히므로 배경을 비운다."""
    size = MASTER * SS
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw_mark(ImageDraw.Draw(img))
    return img.crop(img.getbbox())


def main() -> None:
    assets = (
        Path(__file__).resolve().parent.parent / "ios/Runner/Assets.xcassets"
    )

    icons = assets / "AppIcon.appiconset"
    master = draw_master()
    source_icon = Path(__file__).resolve().parent.parent / "assets/branding"
    source_icon.mkdir(parents=True, exist_ok=True)
    master.save(source_icon / "campon-home-icon-1024.png", format="PNG")
    for name, px in sorted(OUTPUTS.items(), key=lambda kv: kv[1]):
        icon = master if px == MASTER else master.resize((px, px), Image.LANCZOS)
        icon.save(icons / name, format="PNG")
        print(f"{name:30} {px}x{px}")

    # 런치 스토리보드는 이미지를 확대하지 않고 가운데 놓으므로(contentMode=center),
    # 1x 픽셀 크기가 그대로 표시 포인트 크기가 된다.
    launch = assets / "LaunchImage.imageset"
    mark = draw_launch_mark()
    for name, width in (
        ("LaunchImage.png", LAUNCH_WIDTH),
        ("LaunchImage@2x.png", LAUNCH_WIDTH * 2),
        ("LaunchImage@3x.png", LAUNCH_WIDTH * 3),
    ):
        height = round(mark.height * width / mark.width)
        mark.resize((width, height), Image.LANCZOS).save(
            launch / name, format="PNG"
        )
        print(f"{name:30} {width}x{height}")


if __name__ == "__main__":
    main()
