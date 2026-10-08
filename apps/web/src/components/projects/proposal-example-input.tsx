"use client";

import { useEffect, useRef, useState } from "react";
import { FileText, LoaderCircle, Plus, X } from "lucide-react";
import { api, type ProposalExample } from "@/lib/api";

export function exampleState(state: ProposalExample["state"]) {
  return state === "available"
    ? "Готов к просмотру"
    : state === "rejected"
      ? "Не прошёл проверку"
      : "На проверке";
}
export function exampleSize(bytes: number) {
  return bytes < 1024 * 1024
    ? `${Math.max(1, Math.ceil(bytes / 1024))} КБ`
    : `${(bytes / 1024 / 1024).toFixed(1)} МБ`;
}

export function ProposalExampleInput({
  projectId,
  exampleId,
  onChange,
  disabled,
  onBusy,
}: {
  projectId: string;
  exampleId: string | null;
  onChange: (id: string | null) => void;
  disabled: boolean;
  onBusy: (value: boolean) => void;
}) {
  const input = useRef<HTMLInputElement>(null);
  const [example, setExample] = useState<ProposalExample | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const path = `/projects/${projectId}/proposal_examples`;
  useEffect(() => {
    if (!exampleId) {
      setExample(null);
      return;
    }
    let active = true;
    let timer: ReturnType<typeof setTimeout>;
    async function refresh() {
      try {
        const result = await api<ProposalExample>(`${path}/${exampleId}`);
        if (!active) return;
        setExample(result);
        setError("");
        if (result.state === "quarantined") timer = setTimeout(refresh, 15000);
      } catch {
        if (active)
          setError("Не удалось открыть пример. Проверьте соединение или удалите его из черновика.");
      }
    }
    void refresh();
    return () => {
      active = false;
      clearTimeout(timer);
    };
  }, [path, exampleId]);
  function pending(value: boolean) {
    setBusy(value);
    onBusy(value);
  }
  async function upload(file: File) {
    if (file.size === 0 || file.size > 10 * 1024 * 1024) {
      setError("Выберите непустой файл размером до 10 МБ.");
      return;
    }
    pending(true);
    setError("");
    try {
      const body = new FormData();
      body.set("file", file);
      const result = await api<ProposalExample>(path, {
        method: "POST",
        body,
        key: crypto.randomUUID(),
      });
      setExample(result);
      onChange(result.id);
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : "Не удалось загрузить файл.");
    } finally {
      pending(false);
    }
  }
  async function remove() {
    if (!exampleId) return;
    pending(true);
    setError("");
    try {
      await api(`${path}/${exampleId}`, { method: "DELETE" });
      setExample(null);
      onChange(null);
    } catch (failure) {
      // A missing file should not trap a restored draft.
      if (failure && typeof failure === "object" && "status" in failure && failure.status === 404)
        onChange(null);
      else setError(failure instanceof Error ? failure.message : "Не удалось удалить файл.");
    } finally {
      pending(false);
    }
  }
  return (
    <div className="proposal-example">
      <span className="proposal-field-title">
        Пример работы <small>необязательно</small>
      </span>
      <input
        className="visually-hidden"
        ref={input}
        type="file"
        accept=".pdf,.jpg,.jpeg,.png"
        aria-label="Прикрепить пример работы"
        disabled={busy || disabled || !!exampleId}
        onChange={(event) => {
          const file = event.currentTarget.files?.[0];
          event.currentTarget.value = "";
          if (file) void upload(file);
        }}
      />
      {exampleId ? (
        <div className="proposal-file">
          <span className="proposal-file-mark">
            <FileText size={21} />
          </span>
          <div>
            <strong>{example?.filename ?? "Прикреплённый пример"}</strong>
            <span>
              {example
                ? `${exampleSize(example.byte_size)} · ${exampleState(example.state)}`
                : "Загружаем сведения…"}
            </span>
          </div>
          <button
            type="button"
            aria-label="Удалить пример работы"
            disabled={busy || disabled}
            onClick={() => {
              void remove();
            }}
          >
            <X size={17} />
          </button>
        </div>
      ) : (
        <button
          type="button"
          className="proposal-upload"
          disabled={busy || disabled}
          onClick={() => input.current?.click()}
        >
          <span>
            {busy ? <LoaderCircle size={22} className="proposal-spinner" /> : <Plus size={23} />}
          </span>
          <div>
            <strong>{busy ? "Загружаем пример…" : "Добавить файл"}</strong>
            <small>PDF, JPG, PNG · до 10 МБ</small>
          </div>
        </button>
      )}
      {exampleId && (
        <p className="proposal-help">
          Заказчик увидит файл вместе с предложением. Скачать его можно после проверки.
        </p>
      )}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
