/**
 * node:crypto 的最小浏览器实现。
 * 上游流媒体层只使用 md5（Subsonic 鉴权）与 randomBytes（salt），
 * 因此这里内联 MD5，避免在 WebView 内引入 crypto-browserify/process 依赖。
 */
import { Buffer } from "./buffer";

const MD5_SHIFT = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9,
  14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15,
  21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
];

const MD5_TABLE = (() => {
  const table = new Int32Array(64);
  for (let i = 0; i < 64; i++) table[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 2 ** 32) | 0;
  return table;
})();

const rotl = (value: number, shift: number): number => (value << shift) | (value >>> (32 - shift));

const utf8 = (text: string): Uint8Array => new TextEncoder().encode(text);

/**
 * 计算 MD5 摘要
 * @param input - 原始字节
 * @returns 16 字节摘要
 */
const md5 = (input: Uint8Array): Uint8Array => {
  const bitLength = input.length * 8;
  const paddedLength = (((input.length + 8) >>> 6) + 1) << 6;
  const buffer = new Uint8Array(paddedLength);
  buffer.set(input);
  buffer[input.length] = 0x80;
  const view = new DataView(buffer.buffer);
  view.setUint32(paddedLength - 8, bitLength >>> 0, true);
  view.setUint32(paddedLength - 4, Math.floor(bitLength / 0x100000000) >>> 0, true);

  let a0 = 0x67452301;
  let b0 = 0xefcdab89;
  let c0 = 0x98badcfe;
  let d0 = 0x10325476;

  const words = new Int32Array(16);
  for (let offset = 0; offset < paddedLength; offset += 64) {
    for (let i = 0; i < 16; i++) words[i] = view.getInt32(offset + i * 4, true);
    let a = a0;
    let b = b0;
    let c = c0;
    let d = d0;
    for (let i = 0; i < 64; i++) {
      let f: number;
      let g: number;
      if (i < 16) {
        f = (b & c) | (~b & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | (~d & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | ~d);
        g = (7 * i) % 16;
      }
      const next = d;
      d = c;
      c = b;
      b = (b + rotl((a + f + MD5_TABLE[i] + words[g]) | 0, MD5_SHIFT[i])) | 0;
      a = next;
    }
    a0 = (a0 + a) | 0;
    b0 = (b0 + b) | 0;
    c0 = (c0 + c) | 0;
    d0 = (d0 + d) | 0;
  }

  const out = new Uint8Array(16);
  const outView = new DataView(out.buffer);
  outView.setInt32(0, a0, true);
  outView.setInt32(4, b0, true);
  outView.setInt32(8, c0, true);
  outView.setInt32(12, d0, true);
  return out;
};

class Hash {
  private chunks: Uint8Array[] = [];
  private length = 0;

  constructor(private readonly algorithm: string) {}

  /** 追加待摘要内容，返回自身以支持链式调用 */
  update(data: string | Uint8Array): Hash {
    const bytes = typeof data === "string" ? utf8(data) : data;
    this.chunks.push(bytes);
    this.length += bytes.length;
    return this;
  }

  /** 输出摘要 */
  digest(encoding: string = "hex"): Buffer | string {
    if (this.algorithm.replace("-", "").toLowerCase() !== "md5")
      throw new Error(`不支持的摘要算法: ${this.algorithm}`);
    const joined = new Uint8Array(this.length);
    let offset = 0;
    for (const chunk of this.chunks) {
      joined.set(chunk, offset);
      offset += chunk.length;
    }
    const result = Buffer.from(md5(joined));
    return encoding === "hex" ? result.toString("hex") : result;
  }
}

/** 创建摘要对象（仅 md5） */
export const createHash = (algorithm: string): Hash => new Hash(algorithm);

/** 生成密码学安全随机字节 */
export const randomBytes = (size: number): Buffer => {
  const bytes = new Uint8Array(size);
  const webCrypto = (globalThis as { crypto?: Crypto }).crypto;
  if (webCrypto?.getRandomValues) webCrypto.getRandomValues(bytes);
  else for (let i = 0; i < size; i++) bytes[i] = Math.floor(Math.random() * 256);
  return Buffer.from(bytes);
};

/** 生成 RFC 4122 v4 UUID */
export const randomUUID = (): string => {
  const webCrypto = (globalThis as { crypto?: Crypto }).crypto;
  if (webCrypto?.randomUUID) return webCrypto.randomUUID();
  const bytes = new Uint8Array(16);
  if (webCrypto?.getRandomValues) webCrypto.getRandomValues(bytes);
  else for (let i = 0; i < 16; i++) bytes[i] = Math.floor(Math.random() * 256);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, "0"));
  return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex
    .slice(8, 10)
    .join("")}-${hex.slice(10).join("")}`;
};

export default { createHash, randomBytes, randomUUID };
