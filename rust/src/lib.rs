//! SPlayer-iOS 内置网易云 API 服务的 C ABI 封装。
//!
//! 把 `ncm-api-rs` 的 Axum 路由运行在 App 进程内的后台线程上，
//! 仅监听 `127.0.0.1`，供 Swift 端的 `NeteaseAPI` 访问。

use std::net::TcpListener;
use std::sync::atomic::{AtomicBool, AtomicU16, Ordering};

/// 服务是否已启动
static STARTED: AtomicBool = AtomicBool::new(false);
/// 当前监听端口，0 表示未启动
static PORT: AtomicU16 = AtomicU16::new(0);

/// 绑定本地监听端口：优先使用 `preferred`，被占用时回退到系统分配端口。
fn bind_local(preferred: u16) -> Option<TcpListener> {
    if let Ok(listener) = TcpListener::bind(("127.0.0.1", preferred)) {
        return Some(listener);
    }
    TcpListener::bind(("127.0.0.1", 0)).ok()
}

/// 启动内置 API 服务。
///
/// 返回实际监听端口（大于 0），失败时返回负错误码：
/// - `-1`：绑定端口失败
/// - `-2`：读取监听端口失败
/// - `-3`：设置非阻塞失败
/// - `-4`：后台线程创建失败
///
/// 重复调用是幂等的，会直接返回首次启动的端口。
#[no_mangle]
pub extern "C" fn ncm_start_server(preferred_port: u16) -> i32 {
    if STARTED.load(Ordering::SeqCst) {
        return PORT.load(Ordering::SeqCst) as i32;
    }

    let Some(listener) = bind_local(preferred_port) else {
        return -1;
    };
    let Ok(addr) = listener.local_addr() else {
        return -2;
    };
    if listener.set_nonblocking(true).is_err() {
        return -3;
    }
    let port = addr.port();

    let spawned = std::thread::Builder::new()
        .name("ncm-api".into())
        .spawn(move || {
            let Ok(runtime) = tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .enable_all()
                .build()
            else {
                return;
            };

            runtime.block_on(async move {
                let Ok(listener) = tokio::net::TcpListener::from_std(listener) else {
                    return;
                };
                let app = ncm_api_rs::server::build_app(ncm_api_rs::create_client(None));
                let _ = axum::serve(listener, app).await;
            });
        });

    if spawned.is_err() {
        return -4;
    }

    PORT.store(port, Ordering::SeqCst);
    STARTED.store(true, Ordering::SeqCst);
    port as i32
}

/// 当前内置服务端口，0 表示未启动。
#[no_mangle]
pub extern "C" fn ncm_server_port() -> u16 {
    PORT.load(Ordering::SeqCst)
}
