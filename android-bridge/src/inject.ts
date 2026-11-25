// esbuild inject：为上游 config.ts 中的自由变量 Buffer 提供浏览器实现
export { Buffer } from "./stubs/buffer";
