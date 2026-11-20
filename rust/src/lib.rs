//! SPlayer-iOS 内置网易云 API 服务的 C ABI 封装。
//!
//! 把 `ncm-api-rs` 的 Axum 路由运行在 App 进程内的后台线程上，
//! 仅监听 `127.0.0.1`，供 Swift 端的 `NeteaseAPI` 访问。

use std::net::TcpListener;
use std::sync::atomic::{AtomicBool, AtomicU16, Ordering};

use axum::extract::Request;
use axum::http::{header, HeaderMap, StatusCode};
use axum::middleware::{from_fn, Next};
use axum::response::{IntoResponse, Response};

/// 服务是否已启动
static STARTED: AtomicBool = AtomicBool::new(false);
/// 当前监听端口，0 表示未启动
static PORT: AtomicU16 = AtomicU16::new(0);

/// 让登录接口的响应结构与 api-enhanced 保持一致。
///
/// api-enhanced 的部分模块会在 Node 层二次加工响应：
/// - `/login/qr/key`：把底层响应包进 `data` 字段
/// - `/login/qr/check`、`/login/cellphone`、`/login`：把 Set-Cookie 拼成 `cookie` 字段写回 body
async fn normalize_login_response(req: Request, next: Next) -> Response {
    let path = req.uri().path().to_string();
    let response = next.run(req).await;

    let target = matches!(
        path.as_str(),
        "/login/qr/key" | "/login/qr/check" | "/login/cellphone" | "/login"
    );
    if !target {
        return response;
    }

    let status = response.status();
    let headers = response.headers().clone();
    let set_cookies: Vec<String> = headers
        .get_all(header::SET_COOKIE)
        .iter()
        .filter_map(|value| value.to_str().ok())
        .map(str::to_string)
        .collect();

    let body = match axum::body::to_bytes(response.into_body(), 8 * 1024 * 1024).await {
        Ok(body) => body.to_vec(),
        Err(_) => return (StatusCode::INTERNAL_SERVER_ERROR, "读取响应体失败").into_response(),
    };

    let Ok(mut value) = serde_json::from_slice::<serde_json::Value>(&body) else {
        return rebuild(headers, status, body);
    };
    if !value.is_object() {
        return rebuild(headers, status, body);
    }

    let mut changed = false;

    if path == "/login/qr/key" && value.get("data").is_none() {
        // api-enhanced: { data: 底层响应, code: 200 }
        value = serde_json::json!({ "code": 200, "data": value });
        changed = true;
    } else if path != "/login/qr/key"
        && value.get("cookie").is_none()
        && !set_cookies.is_empty()
    {
        let success = path == "/login/qr/check"
            || value.get("code").and_then(|code| code.as_i64()) == Some(200);
        if success {
            value["cookie"] = serde_json::Value::String(set_cookies.join(";"));
            changed = true;
        }
    }

    if changed {
        match serde_json::to_vec(&value) {
            Ok(new_body) => rebuild(headers, status, new_body),
            Err(_) => rebuild(headers, status, body),
        }
    } else {
        rebuild(headers, status, body)
    }
}

/// 用新的响应体重建响应，保留状态、Set-Cookie 等头部并修正 Content-Length。
fn rebuild(mut headers: HeaderMap, status: StatusCode, body: Vec<u8>) -> Response {
    headers.remove(header::CONTENT_LENGTH);
    headers.remove(header::TRANSFER_ENCODING);
    if let Ok(length) = header::HeaderValue::from_str(&body.len().to_string()) {
        headers.insert(header::CONTENT_LENGTH, length);
    }
    (status, headers, body).into_response()
}

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
                let app = ncm_api_rs::server::build_app(ncm_api_rs::create_client(None))
                    .layer(from_fn(normalize_login_response));
                let _ = axum::serve(listener, app).await;
            });

            // 监听意外结束时复位状态，允许后续重新启动
            STARTED.store(false, Ordering::SeqCst);
            PORT.store(0, Ordering::SeqCst);
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

/// 强制重启内置 API 服务。
///
/// 长时间休眠后旧监听可能已经失去响应，仅重试请求无法恢复，需要重新监听。
/// 旧监听线程无法安全停止：优先重新绑定 `preferred_port`，
/// 若仍被旧服务占用则由 `bind_local` 回退到系统分配端口。
/// 返回新端口（大于 0），失败时返回负错误码。
#[no_mangle]
pub extern "C" fn ncm_restart_server(preferred_port: u16) -> i32 {
    STARTED.store(false, Ordering::SeqCst);
    PORT.store(0, Ordering::SeqCst);
    ncm_start_server(preferred_port)
}
