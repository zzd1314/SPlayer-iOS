// 浏览器端 Node 全局垫片：crypto-browserify 依赖 Buffer/process/events
const { Buffer } = require("buffer");
globalThis.Buffer = Buffer;
globalThis.process = require("process");
globalThis.global = globalThis;