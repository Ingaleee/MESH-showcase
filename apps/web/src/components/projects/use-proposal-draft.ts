"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { Project } from "@/lib/api";

type Draft = {
  price: string;
  days: string;
  message: string;
  version: number;
  exampleId: string | null;
};

function validDraft(value: unknown): value is Draft {
  if (!value || typeof value !== "object") return false;
  const draft = value as Record<string, unknown>;
  return (
    typeof draft.price === "string" &&
    draft.price.length <= 30 &&
    typeof draft.days === "string" &&
    draft.days.length <= 3 &&
    typeof draft.message === "string" &&
    draft.message.length <= 5000 &&
    Number.isSafeInteger(draft.version) &&
    Number(draft.version) > 0 &&
    (draft.exampleId === null ||
      (typeof draft.exampleId === "string" && /^[0-9a-f-]{36}$/i.test(draft.exampleId)))
  );
}

export function useProposalDraft(project: Project, accountId: string) {
  const storageKey = `mesh:proposal-draft:v1:${accountId}:${project.id}`;
  const [draft, setDraft] = useState<Draft>({
    price: String(project.budget_minor / (project.currency === "JPY" ? 1 : 100)),
    days: "21",
    message: "",
    version: project.brief_version,
    exampleId: null,
  });
  const [ready, setReady] = useState(false);
  const [feedback, setFeedback] = useState("");
  const [complete, setComplete] = useState(false);
  const snapshot = useRef({ draft, ready, complete });
  useEffect(() => {
    snapshot.current = { draft, ready, complete };
  }, [draft, ready, complete]);
  useEffect(
    () => () => {
      const latest = snapshot.current;
      if (!latest.ready || latest.complete) return;
      try {
        localStorage.setItem(storageKey, JSON.stringify(latest.draft));
      } catch {
        /* The open form reported storage failures. */
      }
    },
    [storageKey],
  );
  useEffect(() => {
    try {
      const value: unknown = JSON.parse(localStorage.getItem(storageKey) ?? "null");
      if (validDraft(value)) {
        setDraft(value);
        setFeedback("Черновик восстановлен из этого браузера");
      }
    } catch {
      setFeedback("Хранилище браузера недоступно. Черновик остаётся в открытой форме.");
    }
    setReady(true);
  }, [storageKey]);
  const save = useCallback(() => {
    if (!ready || complete) return;
    try {
      localStorage.setItem(storageKey, JSON.stringify(draft));
      setFeedback("Черновик сохранён в этом браузере");
    } catch {
      setFeedback("Не удалось сохранить черновик. Оставьте форму открытой.");
    }
  }, [storageKey, draft, ready, complete]);
  useEffect(() => {
    if (!ready || complete) return;
    const timer = window.setTimeout(save, 800);
    window.addEventListener("beforeunload", save);
    return () => {
      clearTimeout(timer);
      window.removeEventListener("beforeunload", save);
    };
  }, [save, ready, complete]);
  const clear = useCallback(() => {
    snapshot.current.complete = true;
    setComplete(true);
    try {
      localStorage.removeItem(storageKey);
    } catch {
      /* Successful submission is kept on the server. */
    }
  }, [storageKey]);
  return { draft, setDraft, ready, feedback, save, clear };
}
