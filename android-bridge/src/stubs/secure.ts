/**
 * 安全存储：优先走 Android Keystore（原生 AES-GCM，密钥不可导出），
 * 原生不可用（Node 冒烟/极端环境）时退化为 localStorage 随机密钥 XOR 混淆，
 * 两者都保持上游要求的「密文 Buffer」形态，配置里再统一 base64。
 *
 * 密文以 `keystore:v1:` 前缀区分：老配置解出的明文会在下次保存时自动迁移。
 */
import { Buffer } from "./buffer";

const KEY_STORAGE = "splayer:sec-key";
const KEYSTORE_PREFIX = "keystore:v1:";

let cachedKey: Uint8Array | null = null;

const randomBytes = (size: number): Uint8Array => {
  const bytes = new Uint8Array(size);
  const webCrypto = (globalThis as { crypto?: Crypto }).crypto;
  if (webCrypto?.getRandomValues) webCrypto.getRandomValues(bytes);
  else for (let i = 0; i < size; i++) bytes[i] = Math.floor(Math.random() * 256);
  return bytes;
};

const loadKey = (): Uint8Array => {
  if (cachedKey) return cachedKey;
  const storage = (globalThis as { localStorage?: Storage }).localStorage;
  const stored = storage?.getItem(KEY_STORAGE);
  if (stored) {
    try {
      cachedKey = Buffer.from(stored, "base64");
      return cachedKey;
    } catch {
      // 损坏时重新生成
    }
  }
  cachedKey = randomBytes(32);
  try {
    storage?.setItem(KEY_STORAGE, Buffer.from(cachedKey).toString("base64"));
  } catch {
    // 存储不可用时仅保留内存密钥
  }
  return cachedKey;
};

const xor = (input: Uint8Array): Uint8Array => {
  const key = loadKey();
  const out = new Uint8Array(input.length);
  for (let i = 0; i < input.length; i++) out[i] = input[i] ^ key[i % key.length];
  return out;
};

const utf8Encode = (text: string): Uint8Array => new TextEncoder().encode(text);
const utf8Decode = (bytes: Uint8Array): string => new TextDecoder("utf-8").decode(bytes);

interface SecureNative {
  secureEncrypt?: (plainText: string) => Promise<unknown>;
  secureDecrypt?: (sealed: string) => Promise<unknown>;
}

const nativeSecure = (): SecureNative | undefined =>
  (globalThis as { api?: { system?: SecureNative } }).api?.system;

/** 原生返回值既可能是字符串，也可能是 { value } 包装 */
const unwrap = (result: unknown): string | null => {
  if (typeof result === "string") return result;
  if (result && typeof result === "object") {
    const value = (result as { value?: unknown }).value;
    if (typeof value === "string") return value;
  }
  return null;
};

export interface DecryptedSecret {
  plainText: string;
  needsReEncrypt: boolean;
}

export const isSecureStorageAvailable = async (): Promise<boolean> => {
  const native = nativeSecure();
  return (
    typeof native?.secureEncrypt === "function" && typeof native?.secureDecrypt === "function"
  );
};

/** 加密明文，返回 Buffer 以支持上游 `.toString("base64")` */
export const encryptSecret = async (plainText: string): Promise<Buffer> => {
  const native = nativeSecure();
  if (typeof native?.secureEncrypt === "function") {
    try {
      const sealed = unwrap(await native.secureEncrypt(plainText));
      if (sealed) return Buffer.from(utf8Encode(KEYSTORE_PREFIX + sealed));
    } catch (error) {
      console.warn("[secure] Keystore 加密失败，退化为本地混淆", error);
    }
  }
  return Buffer.from(xor(utf8Encode(plainText)));
};

/** 解密密文；老格式（XOR）在 Keystore 可用时标记需要重新加密 */
export const decryptSecret = async (buffer: Uint8Array): Promise<DecryptedSecret> => {
  const bytes = buffer instanceof Uint8Array ? buffer : Buffer.from(buffer as ArrayBuffer);
  const text = utf8Decode(bytes);
  if (text.startsWith(KEYSTORE_PREFIX)) {
    const native = nativeSecure();
    if (typeof native?.secureDecrypt !== "function")
      throw new Error("系统安全存储不可用，无法解密已加密的配置");
    const plainText = unwrap(await native.secureDecrypt(text.slice(KEYSTORE_PREFIX.length)));
    if (plainText == null) throw new Error("系统安全存储解密失败");
    return { plainText, needsReEncrypt: false };
  }
  return { plainText: utf8Decode(xor(bytes)), needsReEncrypt: await isSecureStorageAvailable() };
};
