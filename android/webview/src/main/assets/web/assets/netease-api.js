/**
 * netease-api.js 分片加载器。
 *
 * 上游 TS + esbuild 生成的 bundle 约 142KB，单文件超出 GitHub MCP 单次写入上限，
 * 因此按字符切分为 netease-api.partN.js.txt，运行时拼接后以 blob 模块导入。
 *
 * 不使用顶层 await：旧版 WebView（Chromium < 89）会在解析阶段直接报错，
 * 导致整个模块不可用。这里导出 ready Promise，由 bridge.js 等待完成后再取接口。
 */
const PARTS = [
  'netease-api.part0.js.txt',
  'netease-api.part1.js.txt',
  'netease-api.part2.js.txt',
  'netease-api.part3.js.txt',
  'netease-api.part4.js.txt',
  'netease-api.part5.js.txt',
]

const load = async () => {
  const texts = await Promise.all(
    PARTS.map((name) =>
      fetch('/assets/assets/' + name).then((res) => {
        if (!res.ok) throw new Error('netease-api 分片加载失败: ' + name + ' (' + res.status + ')')
        return res.text()
      }),
    ),
  )

  const blobUrl = URL.createObjectURL(new Blob([texts.join('')], { type: 'text/javascript' }))
  try {
    await import(blobUrl)
  } finally {
    URL.revokeObjectURL(blobUrl)
  }

  // entry.ts 通过 globalThis.__Netease 暴露接口；dynamic import 下 esbuild 的
  // global-name 变量只存在于模块作用域，window.NeteaseBridge 作为兼容回退。
  const bridge = window.__Netease || window.NeteaseBridge
  if (!bridge) throw new Error('netease-api.js 未暴露 __Netease')
  return bridge
}

export default load()
