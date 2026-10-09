"use client";

import { useEffect, useRef, useState } from "react";
import { api, type Engagement, type Feedback, type Submission } from "@/lib/api";

export function useWorkHistory(initial: Engagement) {
  const [versions, setVersions] = useState<Submission[]>([]);
  const [comments, setComments] = useState<Feedback[]>([]);
  const [versionsCursor, setVersionsCursor] = useState<string | null | undefined>();
  const [feedbackCursor, setFeedbackCursor] = useState<string | null | undefined>();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const sequence = useRef(0);
  useEffect(() => {
    sequence.current++;
    setVersions([]);
    setComments([]);
    setVersionsCursor(undefined);
    setFeedbackCursor(undefined);
    setLoading(false);
    setError("");
    return () => {
      sequence.current++;
    };
  }, [initial.id]);
  const nextVersions =
    versionsCursor === undefined ? initial.submissions_next_cursor : versionsCursor;
  const nextFeedback = feedbackCursor === undefined ? initial.feedback_next_cursor : feedbackCursor;
  async function load(kind: "versions" | "feedback") {
    const cursor = kind === "versions" ? nextVersions : nextFeedback;
    if (!cursor || loading) return;
    const current = ++sequence.current;
    setLoading(true);
    setError("");
    try {
      const params = new URLSearchParams({
        [kind === "versions" ? "versions_cursor" : "feedback_cursor"]: cursor,
      });
      const page = await api<Engagement>(`/engagements/${initial.id}?${params}`);
      if (current !== sequence.current) return;
      if (kind === "versions") {
        setVersions((previous) => [
          ...new Map([...previous, ...page.submissions].map((row) => [row.id, row])).values(),
        ]);
        setVersionsCursor(page.submissions_next_cursor);
      }
      setComments((previous) => [
        ...new Map([...previous, ...page.feedback].map((row) => [row.id, row])).values(),
      ]);
      if (kind === "feedback") setFeedbackCursor(page.feedback_next_cursor);
    } catch (failure) {
      if (current === sequence.current)
        setError(failure instanceof Error ? failure.message : "Не удалось загрузить историю.");
    } finally {
      if (current === sequence.current) setLoading(false);
    }
  }
  const engagement: Engagement = {
    ...initial,
    submissions: [
      ...new Map([...versions, ...initial.submissions].map((row) => [row.id, row])).values(),
    ].sort((a, b) => b.version - a.version),
    feedback: [
      ...new Map([...comments, ...initial.feedback].map((row) => [row.id, row])).values(),
    ].sort((a, b) => a.created_at.localeCompare(b.created_at)),
  };
  return { engagement, nextVersions, nextFeedback, loading, error, load };
}
