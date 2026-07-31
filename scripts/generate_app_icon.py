#!/usr/bin/env python3
"""CampOn 앱 아이콘을 브랜드 색상으로 생성한다.

1024x1024 마스터를 그린 뒤 iOS AppIcon.appiconset이 요구하는 모든 사이즈를 만든다.
좌표는 1024 기준으로 쓰고, 실제로는 4배 크기로 그린 뒤 축소해 계단 현상을 없앤다.

    python3 scripts/generate_app_icon.py

App Store 규칙상 아이콘에는 알파 채널이 없어야 하고 둥근 모서리를 직접 그리면 안 된다
(iOS가 자동으로 깎는다). 그래서 RGB 모드로 만들고 배경을 가장자리까지 채운다.
"""

from pathlib import Path

from PIL import Image, ImageDraw

# lib/theme.dart의 CampColors와 같은 계열을 쓴다.
SKY_TOP = (47, 82, 64)  # 깊은 숲 그늘
SKY_BOTTOM = (20, 38, 28)
TENT_LIT = (217, 138, 71)  # Wood Amber 밝은 면
TENT_SHADE = (180, 101, 42)  # Wood Amber 그늘진 면
DOOR = (42, 35, 24)  # Ink — 배경 초록과 구분되는 따뜻한 어둠
POLE = (232, 220, 196)
STAR = (245, 239, 225)  # Cream

MASTER = 1024
SS = 4  # supersampling 배율

# (중심 x, 중심 y, 반지름) — 1024 기준
STARS = [
    (232, 239, 15),
    (318, 355, 9),
    (612, 183, 8),
    (760, 215, 19),
    (848, 343, 10),
]

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


def draw_master() -> Image.Image:
    size = MASTER * SS
    img = Image.new("RGB", (size, size), SKY_BOTTOM)
    draw = ImageDraw.Draw(img)

    # 위에서 아래로 어두워지는 배경. 알파를 쓰지 않으려고 직접 한 줄씩 칠한다.
    for y in range(size):
        t = y / (size - 1)
        draw.line(
            [(0, y), (size, y)],
            fill=tuple(
                round(a + (b - a) * t) for a, b in zip(SKY_TOP, SKY_BOTTOM)
            ),
        )

    def scaled(points):
        return [(x * SS, y * SS) for x, y in points]

    for cx, cy, r in STARS:
        draw.ellipse(
            [
                (cx - r) * SS,
                (cy - r) * SS,
                (cx + r) * SS,
                (cy + r) * SS,
            ],
            fill=STAR,
        )

    # 텐트 꼭대기에서 교차하는 폴 두 개
    draw.line(scaled([(472, 268), (552, 348)]), fill=POLE, width=11 * SS)
    draw.line(scaled([(552, 268), (472, 348)]), fill=POLE, width=11 * SS)

    # A형 텐트. 가운데를 기준으로 밝은 면과 그늘진 면을 나눠 입체감을 준다.
    draw.polygon(scaled([(512, 322), (512, 792), (168, 792)]), fill=TENT_LIT)
    draw.polygon(scaled([(512, 322), (856, 792), (512, 792)]), fill=TENT_SHADE)

    # 입구
    draw.polygon(scaled([(512, 500), (584, 792), (440, 792)]), fill=DOOR)

    return img.resize((MASTER, MASTER), Image.LANCZOS)


def main() -> None:
    target = (
        Path(__file__).resolve().parent.parent
        / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    )
    master = draw_master()
    for name, px in sorted(OUTPUTS.items(), key=lambda kv: kv[1]):
        icon = master if px == MASTER else master.resize((px, px), Image.LANCZOS)
        icon.save(target / name, format="PNG")
        print(f"{name:30} {px}x{px}")


if __name__ == "__main__":
    main()
