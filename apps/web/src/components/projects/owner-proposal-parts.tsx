"use client";

import { useEffect, useState } from "react";
import { Download, FileText } from "lucide-react";
import type { Proposal } from "@/lib/api";
import { CreatorPortrait } from "@/components/creators/portrait";
import { exampleSize, exampleState } from "./proposal-example-input";

const demoPortraits: Record<string, number> = {
  "Саша Волкова": 0,
  "Марк Соколов": 1,
  "Лера Орлова": 2,
  "Илья Мельников": 3,
  "Даша Миронова": 4,
  "Никита Лис": 5,
};

export function ProposalAvatar({ proposal }: { proposal: Proposal }) {
  const index = demoPortraits[proposal.creator.display_name];
  return (
    <span className="owner-avatar">
      {index !== undefined ? (
        <CreatorPortrait index={index} />
      ) : (
        <span>{proposal.creator.display_name[0]}</span>
      )}
    </span>
  );
}

export function proposalTime(value: string) {
  return new Intl.DateTimeFormat("ru-RU", {
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(value));
}

export function ProposalExampleView({
  projectId,
  proposal,
  large = false,
}: {
  projectId: string;
  proposal: Proposal;
  large?: boolean;
}) {
  const example = proposal.example;
  const [preview, setPreview] = useState<{ id: string; url: string } | null>(null);
  const [failed, setFailed] = useState(false);
  const path = example
    ? `/api/v1/projects/${projectId}/proposal_examples/${example.id}/download`
    : "";
  useEffect(() => {
    if (!example || example.state !== "available" || !example.content_type.startsWith("image/"))
      return;
    const controller = new AbortController();
    let objectUrl: string | undefined;
    setFailed(false);
    void fetch(path, { credentials: "same-origin", signal: controller.signal })
      .then(async (response) => {
        if (!response.ok || !response.headers.get("content-type")?.startsWith("image/"))
          throw new Error("Preview unavailable");
        const blob = await response.blob();
        if (controller.signal.aborted) return;
        objectUrl = URL.createObjectURL(blob);
        setPreview({ id: example.id, url: objectUrl });
      })
      .catch(() => {
        if (!controller.signal.aborted) setFailed(true);
      });
    return () => {
      controller.abort();
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [path, example?.id, example?.state, example?.content_type]);
  if (!example)
    return (
      <div className="owner-example-empty">
        <FileText size={19} />
        <span>Автор описал подход без вложения</span>
      </div>
    );
  const image = preview?.id === example.id && example.state === "available" ? preview.url : null;
  return (
    <div className={`owner-example ${large ? "is-large" : ""}`}>
      {image ? (
        <img src={image} alt={`Пример автора: ${example.filename}`} />
      ) : (
        <span className="owner-example-icon">
          <FileText size={large ? 34 : 22} />
        </span>
      )}
      <div>
        <strong>{example.filename}</strong>
        <span>
          {exampleSize(example.byte_size)} · {exampleState(example.state)}
        </span>
        {failed && <small>Превью недоступно. Файл можно скачать.</small>}
      </div>
      {example.state === "available" && (
        <a href={path} aria-label={`Скачать ${example.filename}`}>
          <Download size={17} />
        </a>
      )}
    </div>
  );
}
