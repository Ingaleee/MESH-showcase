"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import { ArrowRight, FolderOpen, LockKeyhole } from "lucide-react";
import { api, type Engagement } from "@/lib/api";
import { useSession } from "@/components/session-provider";
import { Workroom } from "@/components/workspace/workroom";

export default function WorkspacePage() {
  const { account, loading, openLogin } = useSession();
  if (!account)
    return (
      <div className="workroom-entry panel empty-state">
        <LockKeyhole size={30} />
        <h1>Моя работа</h1>
        <p>
          {loading
            ? "Подключаем ваше пространство…"
            : "Войдите, чтобы открыть свои проекты и продолжить работу."}
        </p>
        <button className="button primary" disabled={loading} onClick={openLogin}>
          Войти
        </button>
      </div>
    );
  return <Workspace key={account.id} actorId={account.id} />;
}

function Workspace({ actorId }: { actorId: string }) {
  const params = useSearchParams();
  const router = useRouter();
  const requested = params.get("engagement") ?? "";
  const [items, setItems] = useState<Engagement[]>([]);
  const [engagement, setEngagement] = useState<Engagement | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const sequence = useRef(0);
  const refresh = useCallback(async () => {
    const current = ++sequence.current;
    try {
      const { data } = await api<{ data: Engagement[] }>("/engagements");
      let chosen =
        data.find((item) => item.id === requested) ?? (requested ? null : (data[0] ?? null));
      const chosenId = chosen?.id ?? requested;
      if (chosenId) chosen = await api<Engagement>(`/engagements/${encodeURIComponent(chosenId)}`);
      if (current !== sequence.current) return;
      setItems(chosen && !data.some((item) => item.id === chosen.id) ? [chosen, ...data] : data);
      setEngagement(chosen);
      setError("");
    } catch (failure) {
      if (current === sequence.current) {
        setError(failure instanceof Error ? failure.message : "Не удалось открыть проект.");
        setEngagement(null);
      }
    } finally {
      if (current === sequence.current) setLoading(false);
    }
  }, [requested]);
  useEffect(() => {
    setLoading(true);
    setEngagement(null);
    void refresh();
    const timer = setInterval(() => {
      if (document.visibilityState === "visible") void refresh();
    }, 10000);
    return () => {
      sequence.current += 1;
      clearInterval(timer);
    };
  }, [refresh]);
  if (loading)
    return (
      <div className="workroom-entry panel empty-state" role="status">
        Открываем рабочее пространство…
      </div>
    );
  if (error)
    return (
      <div className="workroom-entry panel empty-state">
        <h1>Не удалось открыть проект</h1>
        <p className="error" role="alert">
          {error}
        </p>
        <button className="button" onClick={() => void refresh()}>
          Повторить
        </button>
        <Link href="/workspace">Все мои проекты</Link>
      </div>
    );
  if (!engagement)
    return (
      <div className="workroom-entry panel empty-state">
        <FolderOpen size={32} />
        <h1>Всё начинается с проекта</h1>
        <p>Когда заказчик выберет автора, здесь появятся условия и версии результата.</p>
        <Link className="button primary" href="/#projects">
          Найти проект
          <ArrowRight size={17} />
        </Link>
      </div>
    );
  return (
    <Workroom
      key={engagement.id}
      engagement={engagement}
      actorId={actorId}
      refresh={refresh}
      items={items}
      select={(id) => router.replace(`/workspace?engagement=${id}`, { scroll: false })}
    />
  );
}
