#!/usr/bin/env bash
# SPlayer-Next Android：Rust/FFmpeg 音频核心交叉编译（arm64-v8a）
# 用法：bash tools/rust-android-test/ci-build.sh [jniLibs 目的目录（相对仓库根）]
set -euo pipefail

DEST="${1:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FFMPEG_SRC="$ROOT/tools/ffmpeg-audio"
FFMPEG_COMMIT="16bd156"

# 1. 固定 commit 拉取 ffmpeg-audio（audio-engine 同源解码核心）
if [ ! -d "$FFMPEG_SRC/.git" ]; then
  git clone https://github.com/SPlayer-Dev/ffmpeg-audio.git "$FFMPEG_SRC"
fi
git -C "$FFMPEG_SRC" fetch --depth 1 origin "$FFMPEG_COMMIT" 2>/dev/null || true
git -C "$FFMPEG_SRC" checkout -q "$FFMPEG_COMMIT"
echo "ffmpeg-audio @ $(git -C "$FFMPEG_SRC" rev-parse --short HEAD)"

# 2. NDK 工具链
NDK="${ANDROID_NDK_LATEST_HOME:-}"
if [ -z "$NDK" ]; then
  NDK="$ANDROID_HOME/ndk/$(ls "$ANDROID_HOME/ndk" | sort -V | tail -n 1)"
fi
echo "NDK=$NDK"
TOOL="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
SYSROOT="$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
test -x "$TOOL/aarch64-linux-android24-clang"

# 3. bindgen 目标头文件修复：
#    upstream build.rs 不读取 BINDGEN_EXTRA_CLANG_ARGS，交叉编译时 libclang 会误用
#    宿主 glibc 头（报 bits/libc-header-start.h not found）。此处注入读取逻辑，
#    再由环境变量传入 NDK sysroot（bionic 头）。
python3 - "$FFMPEG_SRC/crates/ffmpeg_audio_sys/build.rs" <<'PY'
import sys

p = sys.argv[1]
s = open(p).read()
anchor = 'builder = builder.clang_arg(format!("--target={target}"));'
if 'BINDGEN_EXTRA_CLANG_ARGS_' in s:
    print('build.rs 已含补丁，跳过')
else:
    assert anchor in s, '未找到 bindgen target 锚点，upstream 结构可能已变化'
    extra = '''
        for key in [
            format!("BINDGEN_EXTRA_CLANG_ARGS_{}", target.replace('-', "_")),
            "BINDGEN_EXTRA_CLANG_ARGS".to_string(),
        ] {
            if let Ok(extra) = env::var(&key) {
                for arg in extra.split_whitespace() {
                    builder = builder.clang_arg(arg);
                }
            }
        }
'''
    s = s.replace(anchor, anchor + extra, 1)
    open(p, 'w').write(s)
    print('build.rs 已注入 BINDGEN_EXTRA_CLANG_ARGS 支持')
PY

# 4. 交叉编译环境
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$TOOL/aarch64-linux-android24-clang"
export CC_aarch64_linux_android="$TOOL/aarch64-linux-android24-clang"
export AR_aarch64_linux_android="$TOOL/llvm-ar"
export LIBCLANG_PATH="${LIBCLANG_PATH:-$(ls -d /usr/lib/llvm-*/lib 2>/dev/null | sort -V | tail -n 1)}"
export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$SYSROOT"
echo "LIBCLANG_PATH=$LIBCLANG_PATH"
echo "BINDGEN_EXTRA_CLANG_ARGS=$BINDGEN_EXTRA_CLANG_ARGS"

# 5. 构建
cd "$ROOT/tools/rust-android-test"
cargo build --release --target aarch64-linux-android

SO="target/aarch64-linux-android/release/librust_android_test.so"
echo "--- JNI 符号 ---"
"$TOOL/llvm-nm" -D "$SO" | grep Java_ || true
ls -l "$SO"

# 6. 输出到 jniLibs
if [ -n "$DEST" ]; then
  mkdir -p "$ROOT/$DEST"
  cp "$SO" "$ROOT/$DEST/"
  ls -l "$ROOT/$DEST"
fi
