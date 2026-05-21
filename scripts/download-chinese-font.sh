#!/bin/bash
# 下载 Noto Sans SC 中文字体

FONTS_DIR="apps/godot-client/assets/resources/fonts"
FONT_FILE="NotoSansSC-Regular.ttf"
FONT_URL="https://github.com/googlefonts/noto-cjk/raw/main/Sans/OTF/SimplifiedChinese/NotoSansSC-Regular.otf"

mkdir -p "$FONTS_DIR"

echo "正在下载 Noto Sans SC 中文字体..."

# 使用 curl 下载
if curl -L -o "$FONTS_DIR/$FONT_FILE" "$FONT_URL"; then
    echo "✓ 字体下载成功: $FONTS_DIR/$FONT_FILE"
else
    echo "✗ 下载失败，请手动下载字体文件"
    echo "下载地址: $FONT_URL"
    echo "保存到: $FONTS_DIR/$FONT_FILE"
fi

# 验证文件
if [ -f "$FONTS_DIR/$FONT_FILE" ]; then
    echo "文件大小: $(du -h "$FONTS_DIR/$FONT_FILE" | cut -f1)"
fi