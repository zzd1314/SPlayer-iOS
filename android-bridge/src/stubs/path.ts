/**
 * node:path 的最小 POSIX 实现：上游 config.ts 只使用 join / dirname。
 */

/** 拼接路径并压缩重复分隔符 */
export const join = (...parts: string[]): string => {
  const joined = parts
    .filter((part) => part !== undefined && part !== null && part !== "")
    .join("/")
    .replace(/\/{2,}/g, "/");
  if (!joined) return ".";
  return joined.length > 1 ? joined.replace(/\/+$/, "") : joined;
};

/** 返回父目录 */
export const dirname = (input: string): string => {
  const normalized = input.replace(/\/+$/, "");
  const index = normalized.lastIndexOf("/");
  if (index < 0) return ".";
  if (index === 0) return "/";
  return normalized.slice(0, index);
};

/** 返回最后一段 */
export const basename = (input: string): string => {
  const normalized = input.replace(/\/+$/, "");
  const index = normalized.lastIndexOf("/");
  return index < 0 ? normalized : normalized.slice(index + 1);
};

export const sep = "/";

export default { join, dirname, basename, sep };
