"use client";

import { useEffect, useRef, useState } from "react";
import { api, type ProjectDetail, type Proposal } from "@/lib/api";
import type { ProposalSort } from "./owner-proposal-list";

export function useOwnerProposals(
  detail: ProjectDetail,
  filters: { query: string; sort: ProposalSort; version: string; ids: string[] | null },
) {
  const [items, setItems] = useState(detail.proposals);
  const [cache, setCache] = useState<Proposal[]>(detail.proposals);
  const [nextCursor, setNextCursor] = useState(detail.next_proposal_cursor);
  const [matchedCount, setMatchedCount] = useState(detail.matched_proposal_count);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const sequence = useRef(0);
  const key = JSON.stringify([
    filters.query.trim().slice(0, 100),
    filters.sort,
    filters.version,
    filters.ids?.slice(0, 100).sort() ?? null,
  ]);
  function parameters(cursor?: string) {
    const [query, sort, version, ids] = JSON.parse(key) as [
      string,
      string,
      string,
      string[] | null,
    ];
    const params = new URLSearchParams({ q: query, sort, brief_filter: version });
    if (ids !== null) params.set("ids", ids.join(","));
    if (cursor) params.set("cursor", cursor);
    return params;
  }
  function remember(rows: Proposal[]) {
    setCache((previous) => [
      ...new Map([...previous, ...rows].map((row) => [row.id, row])).values(),
    ]);
  }
  useEffect(() => {
    const current = ++sequence.current;
    const timer = setTimeout(async () => {
      setLoading(true);
      setError("");
      try {
        const page = await api<ProjectDetail>(`/projects/${detail.project.id}?${parameters()}`);
        if (current !== sequence.current) return;
        setItems(page.proposals);
        remember([...detail.proposals, ...page.proposals]);
        setNextCursor(page.next_proposal_cursor);
        setMatchedCount(page.matched_proposal_count);
      } catch (failure) {
        if (current === sequence.current)
          setError(
            failure instanceof Error ? failure.message : "Не удалось загрузить предложения.",
          );
      } finally {
        if (current === sequence.current) setLoading(false);
      }
    }, 250);
    return () => {
      clearTimeout(timer);
      sequence.current++;
    };
    // The serialized filter key defines this request, including saved IDs.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [detail, key]);
  async function loadMore() {
    if (!nextCursor || loading) return;
    const current = ++sequence.current;
    setLoading(true);
    setError("");
    try {
      const page = await api<ProjectDetail>(
        `/projects/${detail.project.id}?${parameters(nextCursor)}`,
      );
      if (current !== sequence.current) return;
      setItems((previous) => [
        ...new Map([...previous, ...page.proposals].map((row) => [row.id, row])).values(),
      ]);
      remember(page.proposals);
      setNextCursor(page.next_proposal_cursor);
      setMatchedCount(page.matched_proposal_count);
    } catch (failure) {
      if (current === sequence.current)
        setError(failure instanceof Error ? failure.message : "Не удалось загрузить предложения.");
    } finally {
      if (current === sequence.current) setLoading(false);
    }
  }
  return { items, cache, nextCursor, matchedCount, loading, error, loadMore };
}
