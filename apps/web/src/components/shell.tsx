"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  ArrowUpRight,
  Bell,
  BriefcaseBusiness,
  Compass,
  LayoutGrid,
  LogOut,
  Search,
  ShieldCheck,
  Users,
} from "lucide-react";
import { useEffect, useState, type ReactNode } from "react";
import { createConsumer } from "@rails/actioncable";
import { api, type Notification } from "@/lib/api";
import { useSession } from "./session-provider";
import { CreateProjectButton } from "./create-project-button";

const navigation = [
  { href: "/", label: "Проекты", icon: Compass },
  { href: "/creators", label: "Авторы", icon: Users },
  { href: "/workspace", label: "Моя работа", icon: BriefcaseBusiness },
];

export function Shell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const creators = pathname.startsWith("/creators");
  const project = pathname.startsWith("/projects/");
  const workspace = pathname.startsWith("/workspace");
  const landing = pathname === "/" || creators || project || workspace;
  const { account, loading, openLogin, signOut } = useSession();
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [inbox, setInbox] = useState(false);

  useEffect(() => {
    if (!account) return;
    let active = true;
    const refresh = () =>
      api<{ data: Notification[] }>("/notifications")
        .then((result) => {
          if (active) setNotifications(result.data);
        })
        .catch(() => {});
    void refresh();
    const consumer = createConsumer("/cable");
    consumer.subscriptions.create("NotificationsChannel", { received: refresh });
    const timer = setInterval(refresh, 15000);
    return () => {
      active = false;
      clearInterval(timer);
      consumer.disconnect();
    };
  }, [account]);

  async function read(notification: Notification) {
    await api(`/notifications/${notification.id}`, { method: "PATCH" });
    setNotifications((items) =>
      items.map((item) =>
        item.id === notification.id ? { ...item, read_at: new Date().toISOString() } : item,
      ),
    );
    setInbox(false);
  }

  return (
    <div className={landing ? "landing-shell" : "app-shell"}>
      {!landing && (
        <aside className="sidebar">
          <Link href="/" className="wordmark" aria-label="MESH — главная">
            <span className="brand-mark">✳</span>MESH<span className="wordmark-dot">.</span>
          </Link>
          <div className="sidebar-label">CREATOR NETWORK</div>
          <nav aria-label="Основная навигация">
            {navigation.map(({ href, label, icon: Icon }) => (
              <Link
                key={href}
                href={href}
                className={`nav-item ${pathname === href || (href !== "/" && pathname.startsWith(href)) ? "active" : ""}`}
              >
                <Icon size={19} />
                {label}
                {pathname === href && <span className="nav-dot" />}
              </Link>
            ))}
            {account?.operator && (
              <Link
                href="/operations"
                className={`nav-item ${pathname === "/operations" ? "active" : ""}`}
              >
                <ShieldCheck size={19} />
                Операции
              </Link>
            )}
            {account?.operator && (
              <Link
                href="/publishing"
                className={"nav-item " + (pathname === "/publishing" ? "active" : "")}
              >
                <ShieldCheck size={19} />
                Publishing Lab
              </Link>
            )}
          </nav>
          <div className="sidebar-bottom">
            <div className="sidebar-card">
              <LayoutGrid size={21} />
              <strong>
                Связи, из которых
                <br />
                рождается работа.
              </strong>
              <span>Авторы × идеи × возможности</span>
              <ArrowUpRight size={18} />
            </div>
            <span className="sidebar-footer">MESH / рабочая версия · 2026</span>
          </div>
        </aside>
      )}
      <div className={landing ? "landing-main" : "main-column"}>
        <header className={landing ? "landing-header" : "topbar"}>
          {landing ? (
            <>
              <Link href="/" className="landing-wordmark" aria-label="MESH — главная">
                MESH
              </Link>
              <nav className="landing-nav" aria-label="Основная навигация">
                <Link href="/#projects" aria-current={project ? "page" : undefined}>
                  Проекты
                </Link>
                <Link href="/creators" aria-current={creators ? "page" : undefined}>
                  Авторы
                </Link>
                <Link href="/#categories">Категории</Link>
                <Link href="/#how-it-works">Как это работает</Link>
                {account && <Link href="/workspace">Моя работа</Link>}
                {account?.operator && <Link href="/operations">Операции</Link>}
                {account?.operator && <Link href="/publishing">Publishing Lab</Link>}
              </nav>
            </>
          ) : (
            <span className="breadcrumb">
              Пространство возможностей <span>/</span>{" "}
              <strong>
                {pathname === "/" || pathname.startsWith("/projects")
                  ? "Проекты"
                  : pathname.startsWith("/creators")
                    ? "Авторы"
                    : pathname.startsWith("/operations")
                      ? "Операции"
                      : "Моя работа"}
              </strong>
            </span>
          )}
          <div className="topbar-actions">
            {project || workspace ? (
              <Link
                href="/#project-search"
                className="icon-button landing-search"
                aria-label="Найти проект"
              >
                <Search size={21} />
              </Link>
            ) : landing ? (
              <button
                className="icon-button landing-search"
                aria-label={creators ? "Найти автора" : "Найти проект"}
                onClick={() => {
                  const input = document.querySelector<HTMLInputElement>(
                    creators ? "#creator-search" : "#project-search",
                  );
                  input?.scrollIntoView({ block: "center" });
                  input?.focus({ preventScroll: true });
                }}
              >
                <Search size={21} />
              </button>
            ) : (
              <span className="preview-badge">PREVIEW</span>
            )}
            {account ? (
              <>
                <div className="inbox-wrap">
                  <button
                    className="icon-button"
                    aria-label="Уведомления"
                    onClick={() => setInbox(!inbox)}
                  >
                    <Bell size={19} />
                    {notifications.some((item) => !item.read_at) && <span className="unread-dot" />}
                  </button>
                  {inbox && (
                    <div className="inbox">
                      <strong>Ваши обновления</strong>
                      {notifications.length === 0 ? (
                        <p className="muted">Пока тихо. Новые события появятся здесь.</p>
                      ) : (
                        notifications.slice(0, 8).map((item) => (
                          <Link
                            key={item.id}
                            href={item.resource_path}
                            onClick={() => {
                              void read(item);
                            }}
                            className={item.read_at ? "notification" : "notification unread"}
                          >
                            <strong>{item.title}</strong>
                            <span>{item.body}</span>
                          </Link>
                        ))
                      )}
                    </div>
                  )}
                </div>
                <span className="account-avatar">{account.display_name.slice(0, 1)}</span>
                <span className="account-name">{account.display_name}</span>
                <button
                  className="icon-button"
                  aria-label="Выйти"
                  onClick={() => {
                    void signOut();
                  }}
                >
                  <LogOut size={17} />
                </button>
              </>
            ) : (
              <button
                className={landing ? "landing-login" : "button compact"}
                disabled={loading}
                onClick={openLogin}
              >
                Войти {!landing && <ArrowUpRight size={16} />}
              </button>
            )}
            {landing && <CreateProjectButton ariaLabel="Создать проект через меню" />}
          </div>
        </header>
        <main id="main-content">{children}</main>
        <footer className={landing ? "landing-footer" : "page-footer"}>
          <span>Сделано для людей, которые создают.</span>
          <span>MESH © 2026</span>
        </footer>
      </div>
    </div>
  );
}
