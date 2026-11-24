//! SPlayer-Next Android：Rust 音频引擎最小验证 crate。
//!
//! 目标：验证 ffmpeg_audio（FFmpeg bundled 交叉编译）能否为 aarch64-linux-android
//! 产出可加载的 cdylib，并通过 JNI 出口暴露，为 audio-engine 全量移植铺路。

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};

/// JNI 冒烟测试：整数加法（验证 .so 可加载、符号可绑定）。
#[no_mangle]
pub extern "C" fn Java_com_splayer_next_web_RustBridge_nativeAdd(a: c_int, b: c_int) -> c_int {
    a + b
}

/// JNI：返回 FFmpeg 版本信息字符串（验证 FFmpeg 静态链接进 .so 且可调用）。
/// Java 侧负责释放 returned char*（nativeFreeString）。
#[no_mangle]
pub extern "C" fn Java_com_splayer_next_web_RustBridge_nativeFfmpegVersion() -> *mut c_char {
    let info = ffmpeg_audio::sys::av_version_info();
    let cstr = unsafe { CStr::from_ptr(info) };
    // 拷贝为 Rust 分配的 CString，交由 Java 侧通过 nativeFreeString 释放
    match CString::new(cstr.to_bytes().to_vec()) {
        Ok(s) => s.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// 释放 nativeFfmpegVersion 返回的字符串。
#[no_mangle]
pub extern "C" fn Java_com_splayer_next_web_RustBridge_nativeFreeString(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { drop(CString::from_raw(ptr)) };
    }
}
