#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 启动内置网易云 API 服务。
/// 返回实际监听端口（大于 0），失败时返回负错误码；重复调用返回既有端口。
int32_t ncm_start_server(uint16_t preferred_port);

/// 当前内置服务端口，0 表示未启动。
uint16_t ncm_server_port(void);

/// 强制重启内置 API 服务（用于长时间休眠后监听失效的恢复）。
/// 返回新监听端口（大于 0），失败时返回负错误码。
int32_t ncm_restart_server(uint16_t preferred_port);

#ifdef __cplusplus
}
#endif
