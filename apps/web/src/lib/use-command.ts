"use client";

import { useRef, useState } from "react";
import { api } from "./api";

export function useCommand() {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const intent = useRef<{ fingerprint: string; key: string } | null>(null);

  async function execute<T>(path: string, body?: unknown, method = "POST") {
    const fingerprint = JSON.stringify([path, method, body]);
    if (intent.current?.fingerprint !== fingerprint) {
      intent.current = { fingerprint, key: crypto.randomUUID() };
    }
    setPending(true);
    setError("");
    try {
      const result = await api<T>(path, { method, body, key: intent.current.key });
      intent.current = null;
      return result;
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : "Не удалось выполнить действие.");
      throw failure;
    } finally {
      setPending(false);
    }
  }

  return { execute, pending, error, clearError: () => setError("") };
}
