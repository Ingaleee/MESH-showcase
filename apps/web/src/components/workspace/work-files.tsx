"use client";

import { useEffect, useState } from "react";
import { Download, FileArchive, FileText, ImageIcon } from "lucide-react";
import type { WorkFile } from "@/lib/api";

export function fileSize(bytes: number) {
  return bytes < 1024 * 1024
    ? `${Math.ceil(bytes / 1024)} КБ`
    : `${(bytes / 1024 / 1024).toFixed(1)} МБ`;
}

export const fileStates = {
  quarantined: "Проверяется",
  available: "Доступен",
  rejected: "Не прошёл проверку",
};

export function filePath(engagementId: string, fileId: string) {
  return `/api/v1/engagements/${engagementId}/work_files/${fileId}/download`;
}

export function WorkImage({ engagementId, file }: { engagementId: string; file: WorkFile }) {
  const [preview, setPreview] = useState<{ id: string; url: string } | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    if (file.state !== "available" || !file.content_type.startsWith("image/")) return;
    const controller = new AbortController();
    let objectUrl: string | undefined;
    setFailed(false);
    void fetch(filePath(engagementId, file.id), {
      credentials: "same-origin",
      signal: controller.signal,
    })
      .then(async (response) => {
        if (!response.ok || !response.headers.get("content-type")?.startsWith("image/"))
          throw new Error("Preview unavailable");
        const blob = await response.blob();
        if (controller.signal.aborted) return;
        objectUrl = URL.createObjectURL(blob);
        setPreview({ id: file.id, url: objectUrl });
      })
      .catch(() => {
        if (!controller.signal.aborted) setFailed(true);
      });
    return () => {
      controller.abort();
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [engagementId, file.id, file.state, file.content_type]);
  return preview?.id === file.id && file.state === "available" ? (
    <img src={preview.url} alt={`Результат работы: ${file.filename}`} />
  ) : (
    <span className="workroom-image-placeholder">
      <ImageIcon size={30} />
      <span>{failed ? "Превью недоступно" : fileStates[file.state]}</span>
    </span>
  );
}

export function WorkFileLink({ engagementId, file }: { engagementId: string; file: WorkFile }) {
  const Icon = file.content_type.includes("zip")
    ? FileArchive
    : file.content_type.startsWith("image/")
      ? ImageIcon
      : FileText;
  const content = (
    <>
      <span
        className={`workroom-file-icon ${file.content_type === "application/pdf" ? "is-pdf" : ""}`}
      >
        <Icon size={20} />
      </span>
      <span>
        <strong>{file.filename}</strong>
        <small>
          {fileSize(file.byte_size)} · {fileStates[file.state]}
        </small>
      </span>
      {file.state === "available" && <Download size={15} />}
    </>
  );
  return file.state === "available" ? (
    <a
      className="workroom-file"
      href={filePath(engagementId, file.id)}
      aria-label={`Скачать ${file.filename}`}
    >
      {content}
    </a>
  ) : (
    <div className="workroom-file">{content}</div>
  );
}
