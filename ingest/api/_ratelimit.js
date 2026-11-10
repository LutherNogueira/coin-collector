// A small per-client limit on how many batches are accepted. Serverless instances do not share memory, so this is a
// best-effort brake against a script hammering one instance, not a guarantee: the real fence is a rate-limit rule in
// the Vercel firewall (see docs/adr/0008). It exists so that one noisy client cannot fill the store from one instance.

export function createLimiter({ limit, windowMs, maxKeys = 5000, now = Date.now }) {
  const windows = new Map();   // key -> { start, count }
  return {
    allow(key) {
      const t = now();
      let w = windows.get(key);
      if (!w || t - w.start >= windowMs) {
        if (windows.size >= maxKeys) {
          for (const [k, v] of windows) if (t - v.start >= windowMs) windows.delete(k);
          if (windows.size >= maxKeys) windows.clear();   // under a flood of keys, forget everyone rather than grow
        }
        w = { start: t, count: 0 };
        windows.set(key, w);
      }
      w.count += 1;
      return w.count <= limit;
    },
  };
}
