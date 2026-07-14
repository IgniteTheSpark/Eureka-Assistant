function memoryStorage(): Storage {
  const values = new Map<string, string>();
  return {
    get length() {
      return values.size;
    },
    clear: () => values.clear(),
    getItem: (key) => values.get(key) ?? null,
    key: (index) => [...values.keys()][index] ?? null,
    removeItem: (key) => values.delete(key),
    setItem: (key, value) => values.set(key, String(value)),
  };
}

for (const key of ["localStorage", "sessionStorage"] as const) {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, key);
  if (!descriptor || descriptor.get) {
    Object.defineProperty(globalThis, key, {
      configurable: true,
      value: memoryStorage(),
    });
  }
}
