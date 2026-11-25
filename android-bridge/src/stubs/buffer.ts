/**
 * 最小 Buffer 垫片：上游 config.ts 只用到 base64 / utf-8 / latin1 三种编码，
 * 不引入完整 node buffer 依赖，避免 WebView 里额外的 process 依赖。
 */

const encodeBase64 = (bytes: Uint8Array): string => {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
};

const decodeBase64 = (text: string): Uint8Array => {
  const binary = atob(text.replace(/-/g, "+").replace(/_/g, "/"));
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
};

const utf8Encode = (text: string): Uint8Array => {
  if (typeof TextEncoder !== "undefined") return new TextEncoder().encode(text);
  const escaped = unescape(encodeURIComponent(text));
  const out = new Uint8Array(escaped.length);
  for (let i = 0; i < escaped.length; i++) out[i] = escaped.charCodeAt(i);
  return out;
};

const utf8Decode = (bytes: Uint8Array): string => {
  if (typeof TextDecoder !== "undefined") return new TextDecoder("utf-8").decode(bytes);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return decodeURIComponent(escape(binary));
};

const encodeHex = (bytes: Uint8Array): string => {
  let out = "";
  for (const byte of bytes) out += byte.toString(16).padStart(2, "0");
  return out;
};

const latin1Decode = (bytes: Uint8Array): string => {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return binary;
};

const latin1Encode = (text: string): Uint8Array => {
  const out = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) out[i] = text.charCodeAt(i) & 0xff;
  return out;
};

const isByteArray = (value: unknown): value is Uint8Array =>
  value instanceof Uint8Array || value instanceof ArrayBuffer;

const toBytes = (value: Uint8Array | ArrayBuffer): Uint8Array =>
  value instanceof Uint8Array
    ? new Uint8Array(value.buffer, value.byteOffset, value.byteLength)
    : new Uint8Array(value);

/** WebView 内可用的 Buffer 子集，保持 `Buffer.from(...).toString(...)` 语义 */
export class Buffer extends Uint8Array {
  /**
   * 从字符串或字节数组创建 Buffer
   * @param input - 输入内容
   * @param encoding - 字符串编码
   * @returns 字节缓冲
   */
  static from(input: string | ArrayBuffer | Uint8Array | number[], encoding?: string): Buffer {
    if (typeof input === "string") {
      const normalized = (encoding ?? "utf8").toLowerCase();
      if (normalized === "base64") return new Buffer(decodeBase64(input)) as Buffer;
      if (normalized === "latin1" || normalized === "binary")
        return new Buffer(latin1Encode(input)) as Buffer;
      return new Buffer(utf8Encode(input)) as Buffer;
    }
    if (typeof input === "number") return new Buffer(new Uint8Array(0)) as Buffer;
    return new Buffer(toBytes(input as Uint8Array | ArrayBuffer)) as Buffer;
  }

  /** 拼接多个字节片段 */
  static concat(chunks: (Uint8Array | ArrayBuffer)[]): Buffer {
    const total = chunks.reduce((sum, chunk) => sum + toBytes(chunk).byteLength, 0);
    const out = new Buffer(new Uint8Array(total)) as Buffer;
    let offset = 0;
    for (const chunk of chunks) {
      const bytes = toBytes(chunk);
      out.set(bytes, offset);
      offset += bytes.byteLength;
    }
    return out;
  }

  /**
   * 按编码转换回字符串
   * @param encoding - utf8 / latin1 / base64
   * @param start - 起始字节
   * @param end - 结束字节
   */
  toString(encoding: string = "utf8", start = 0, end = this.length): string {
    const bytes = this.subarray(start, end);
    const normalized = encoding.toLowerCase();
    if (normalized === "base64") return encodeBase64(bytes);
    if (normalized === "hex") return encodeHex(bytes);
    if (normalized === "latin1" || normalized === "binary") return latin1Decode(bytes);
    return utf8Decode(bytes);
  }
}

export default Buffer;
