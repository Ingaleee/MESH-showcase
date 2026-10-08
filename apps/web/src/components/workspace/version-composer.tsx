"use client";

import { useEffect, useRef, useState } from "react";
import { ArrowRight, Check, FileUp, LoaderCircle, Plus, X } from "lucide-react";
import { api, type Engagement, type WorkFile } from "@/lib/api";
import { useCommand } from "@/lib/use-command";
import { Modal } from "@/components/modal";
import { fileSize, fileStates } from "./work-files";

type Draft = { title: string; content: string; ready: boolean; files: string[] };
export function VersionComposer({
  engagement,
  actorId,
  onClose,
  refresh,
}: {
  engagement: Engagement;
  actorId: string;
  onClose: () => void;
  refresh: () => Promise<void>;
}) {
  const draftKey = `mesh:work-version:${actorId}:${engagement.id}`;
  const [draft, setDraft] = useState<Draft>({ title: "", content: "", ready: true, files: [] });
  const [files, setFiles] = useState<WorkFile[]>([]);
  const [restored, setRestored] = useState(false);
  const [busy, setBusy] = useState(false);
  const [dragging, setDragging] = useState(false);
  const [error, setError] = useState("");
  const [storageError, setStorageError] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  const alive = useRef(true);
  const command = useCommand();
  const pending = busy || command.pending;

  useEffect(() => {
    alive.current = true;
    let active = true;
    let stored: Draft | null = null;
    try {
      const value = JSON.parse(localStorage.getItem(draftKey) ?? "null");
      if (
        value &&
        typeof value.title === "string" &&
        typeof value.content === "string" &&
        typeof value.ready === "boolean" &&
        Array.isArray(value.files) &&
        value.files.every((id: unknown) => typeof id === "string")
      )
        stored = value;
    } catch {
      setStorageError(true);
    }
    if (stored) setDraft(stored);
    void api<{ data: WorkFile[] }>(`/engagements/${engagement.id}/work_files`)
      .then(({ data }) => {
        if (!active) return;
        const available = data.filter((file) => file.submission_id === null);
        const ids = (stored?.files ?? []).filter((id) => available.some((file) => file.id === id));
        setFiles(available.filter((file) => ids.includes(file.id)));
        setDraft((current) => ({ ...current, files: ids }));
        setRestored(true);
      })
      .catch((failure: Error) => {
        if (active) setError(failure.message);
      });
    return () => {
      active = false;
      alive.current = false;
    };
  }, [draftKey, engagement.id]);

  useEffect(() => {
    if (!restored) return;
    try {
      localStorage.setItem(draftKey, JSON.stringify(draft));
    } catch {
      setStorageError(true);
    }
  }, [draft, draftKey, restored]);

  useEffect(() => {
    if (!files.some((file) => file.state === "quarantined")) return;
    const timer = setInterval(() => {
      void api<{ data: WorkFile[] }>(`/engagements/${engagement.id}/work_files`)
        .then(({ data }) => {
          if (alive.current)
            setFiles((current) =>
              current.map((file) => data.find((item) => item.id === file.id) ?? file),
            );
        })
        .catch(() => {});
    }, 5000);
    return () => clearInterval(timer);
  }, [engagement.id, files]);

  async function upload(selected: File[]) {
    if (pending || !restored) return;
    setError("");
    if (files.length + selected.length > 8) {
      setError("В одной версии может быть до 8 файлов.");
      return;
    }
    if (selected.some((file) => file.size === 0 || file.size > 20 * 1024 * 1024)) {
      setError("Выберите непустые файлы размером до 20 МБ каждый.");
      return;
    }
    setBusy(true);
    try {
      for (const file of selected) {
        const body = new FormData();
        body.set("file", file);
        const result = await api<WorkFile>(`/engagements/${engagement.id}/work_files`, {
          method: "POST",
          body,
          key: crypto.randomUUID(),
        });
        if (!alive.current) return;
        setFiles((current) => [...current, result]);
        setDraft((current) => ({ ...current, files: [...current.files, result.id] }));
      }
    } catch (failure) {
      if (alive.current)
        setError(failure instanceof Error ? failure.message : "Не удалось загрузить файл.");
    } finally {
      if (alive.current) setBusy(false);
    }
  }

  async function remove(id: string) {
    setBusy(true);
    setError("");
    try {
      await api(`/engagements/${engagement.id}/work_files/${id}`, { method: "DELETE" });
      setFiles((current) => current.filter((file) => file.id !== id));
      setDraft((current) => ({
        ...current,
        files: current.files.filter((fileId) => fileId !== id),
      }));
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : "Не удалось удалить файл.");
    } finally {
      setBusy(false);
    }
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (pending || !restored) return;
    try {
      await command.execute(`/engagements/${engagement.id}/submit`, {
        title: draft.title.trim(),
        content: draft.content.trim(),
        ready_for_acceptance: draft.ready,
        file_ids: draft.files,
      });
      try {
        localStorage.removeItem(draftKey);
      } catch {}
      await refresh();
      onClose();
    } catch {}
  }

  return (
    <Modal
      title="Новая версия"
      className="workroom-composer"
      onClose={() => {
        if (!pending) onClose();
      }}
    >
      <p className="workroom-modal-lead">
        Версия {(engagement.submissions[0]?.version ?? 0) + 1} · {engagement.terms.title}
      </p>
      <form onSubmit={submit} className="form-stack">
        <label>
          Название версии
          <input
            value={draft.title}
            required
            maxLength={160}
            placeholder="Например, NORA — визуальная система v3"
            disabled={pending}
            onChange={(event) => setDraft({ ...draft, title: event.target.value })}
          />
        </label>
        <div className="workroom-upload-heading">
          <strong>Файлы результата</strong>
          <span>{files.length} / 8</span>
        </div>
        <input
          ref={input}
          type="file"
          className="visually-hidden"
          aria-label="Файлы результата"
          multiple
          accept=".pdf,.png,.jpg,.jpeg,.zip"
          disabled={pending || !restored}
          onChange={(event) => {
            void upload(Array.from(event.target.files ?? []));
            event.target.value = "";
          }}
        />
        <button
          type="button"
          className={`workroom-drop ${dragging ? "is-dragging" : ""}`}
          disabled={pending || !restored}
          onClick={() => input.current?.click()}
          onDragOver={(event) => {
            event.preventDefault();
            setDragging(true);
          }}
          onDragLeave={() => setDragging(false)}
          onDrop={(event) => {
            event.preventDefault();
            setDragging(false);
            void upload(Array.from(event.dataTransfer.files));
          }}
        >
          {busy ? <LoaderCircle className="workroom-spinner" size={27} /> : <FileUp size={27} />}
          <strong>Перетащите файлы или выберите их</strong>
          <span>PDF, JPG, PNG, ZIP · до 20 МБ каждый</span>
        </button>
        {files.length > 0 && (
          <ul className="workroom-upload-list">
            {files.map((file) => (
              <li key={file.id}>
                <Plus size={17} />
                <span>
                  <strong>{file.filename}</strong>
                  <small>
                    {fileSize(file.byte_size)} · {fileStates[file.state]}
                  </small>
                </span>
                <button
                  type="button"
                  className="icon-button"
                  aria-label={`Удалить ${file.filename}`}
                  disabled={pending}
                  onClick={() => void remove(file.id)}
                >
                  <X size={17} />
                </button>
              </li>
            ))}
          </ul>
        )}
        {files.some((file) => file.state === "quarantined") && (
          <p className="workroom-help">
            Файлы можно передать сейчас. Скачивание откроется после проверки.
          </p>
        )}
        <label>
          Комментарий заказчику
          <textarea
            aria-label="Комментарий заказчику"
            value={draft.content}
            required
            maxLength={20000}
            rows={5}
            placeholder="Что изменилось и на что обратить внимание?"
            disabled={pending}
            onChange={(event) => setDraft({ ...draft, content: event.target.value })}
          />
        </label>
        <label className="workroom-check">
          <input
            type="checkbox"
            checked={draft.ready}
            disabled={pending}
            onChange={(event) => setDraft({ ...draft, ready: event.target.checked })}
          />
          <span>
            <strong>Считаю эту версию готовой к принятию</strong>
            <small>Без отметки версия будет передана для обсуждения.</small>
          </span>
        </label>
        {(error || command.error) && (
          <p className="error" role="alert">
            {error || command.error}
          </p>
        )}
        <button
          className="button primary workroom-wide"
          disabled={pending || !restored || files.some((file) => file.state === "rejected")}
        >
          {command.pending ? "Передаём…" : "Передать заказчику"}
          <ArrowRight size={18} />
        </button>
        <p className="workroom-draft-note">
          <Check size={14} />
          {storageError
            ? "Сохранение на устройстве недоступно. Не закрывайте форму."
            : "Черновик сохраняется на этом устройстве"}
        </p>
      </form>
    </Modal>
  );
}
