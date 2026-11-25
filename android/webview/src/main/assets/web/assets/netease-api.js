/**
 * netease-api.js 分片加载器。
 *
 * 上游 TS + esbuild 生成的 bundle 约 142KB，单文件超出 GitHub MCP 单次写入上限，
 * 因此按字符切分为 netease-api.partN.js.txt，运行时拼接后以 blob 模块导入。
 * 顶层 await 保证 import('/assets/netease-api.js') 在 bundle 真正执行完（挂载
 * window.__Netease）之后才 resolve。
 */
const PARTS = [
  'netease-api.part0.js.txt',
  'netease-api.part1.js.txt',
  'netease-api.part2.js.txt',
  'netease-api.part3.js.txt',
  'netease-api.part4.js.txt',
  'netease-api.part5.js.txt',
]

const texts = await Promise.all(
  PARTS.map((name) =>
    fetch('/assets/' + name).then((res) => {
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
