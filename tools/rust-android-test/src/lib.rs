//! SPlayer-Next Android：Rust 音频引擎最小验证 crate。
//!
//! 验证 ffmpeg_audio（FFmpeg bundled）可为 aarch64-linux-android 产出 cdylib，
//! 并通过 JNI 出口暴露，作为原 Rust audio-engine 迁移的实测依据。

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};

/// FFmpeg 版本串（如 "n9.0.2"），来自静态链接进 .so 的 libavutil。
fn ffmpeg_version() -> String {
    let p = unsafe { ffmpeg_audio::sys::av_version_info() };
    if p.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned()
}

/// JNI 冒烟测试：整数加法（验证 .so 可加载、符号可绑定）。
#[no_mangle]
pub extern "C" fn Java_com_splayer_next_web_api_RustBridge_nativeAdd(a: c_int, b: c_int) -> c_int {
    a + b
}

/// JNI：FFmpeg 主版本号（"n9.0.2" → 9）；失败返回 -1。
/// 返回 int 而非字符串指针，避免 Kotlin 侧直接处理 C 内存。
#[no_mangle]
pub extern "C" fn Java_com_splayer_next_web_api_RustBridge_nativeFfmpegMajor() -> c_int {
    ffmpeg_version()
        .trim_start_matches(|c: char| !c.is_ascii_digit())
        .split('.')
        .next()
        .and_then(|s| s.parse::<c_int>().ok())
        .unwrap_or(-1)
}

/// JNI：返回 FFmpeg 版本串的 C 指针（供后续完整引擎层使用）。
#[no_mangle]
pub extern "C" fn Java_com_splayer_next_web_api_RustBridge_nativeFfmpegVersionPtr() -> *mut c_char {
    match CString::new(ffmpeg_version()) {
        Ok(s) => s.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// 释放 nativeFfmpegVersionPtr 返回的字符串。
#[no_mangle]
pub extern "C" fn Java_com_splayer_next_web_api_RustBridge_nativeFreeString(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(CString::from_raw(ptr)) };
    }
}
