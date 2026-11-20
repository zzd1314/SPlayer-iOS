#!/usr/bin/env bash
# 编译 Rust 内置 API 静态库（Xcode Run Script 与 CI 共用）
set -euo pipefail

# Xcode 脚本环境的 PATH 可能缺少 cargo，主动补齐
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: 未找到 cargo，请先安装 Rust：https://rustup.rs" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SDK="${PLATFORM_NAME:-iphoneos}"
ARCHS="${ARCHS:-arm64}"
OUT_DIR="$SCRIPT_DIR/out/$SDK"
mkdir -p "$OUT_DIR"

LIBS=()
for ARCH in $ARCHS; do
  case "$SDK-$ARCH" in
    iphoneos-arm64) TARGET="aarch64-apple-ios" ;;
    iphonesimulator-arm64) TARGET="aarch64-apple-ios-sim" ;;
    iphonesimulator-x86_64) TARGET="x86_64-apple-ios" ;;
    *)
      echo "warning: 跳过不支持的架构 $SDK $ARCH" >&2
      continue
      ;;
  esac

  if ! rustup target list --installed 2>/dev/null | grep -qx "$TARGET"; then
    rustup target add "$TARGET"
  fi

  echo "==> cargo build --release --target $TARGET"
  CARGO_TARGET_DIR="$SCRIPT_DIR/target" \
    cargo build --manifest-path "$SCRIPT_DIR/Cargo.toml" --release --target "$TARGET"

  LIBS+=("$SCRIPT_DIR/target/$TARGET/release/libncm_api_ios.a")
done

if [ "${#LIBS[@]}" -eq 0 ]; then
  echo "error: 没有可用的 Rust 静态库产物" >&2
  exit 1
fi

if [ "${#LIBS[@]}" -eq 1 ]; then
  cp "${LIBS[0]}" "$OUT_DIR/libncm_api_ios.a"
else
  lipo -create "${LIBS[@]}" -output "$OUT_DIR/libncm_api_ios.a"
fi

echo "==> 静态库已生成：$OUT_DIR/libncm_api_ios.a"
