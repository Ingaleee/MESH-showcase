"use client";

import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from "react";
import { api, setCsrfToken, type Account, type Session } from "@/lib/api";
import { Modal } from "./modal";

type SessionContext = {
  account: Account | null;
  loading: boolean;
  openLogin: () => void;
  signOut: () => Promise<void>;
};
const Context = createContext<SessionContext | null>(null);

export function SessionProvider({ children }: { children: ReactNode }) {
  const [account, setAccount] = useState<Account | null>(null);
  const [loading, setLoading] = useState(true);
  const [login, setLogin] = useState(false);
  const [error, setError] = useState("");
  const initialSession = useRef<Promise<Session> | null>(null);

  function apply(session: Session) {
    setAccount(session.account);
    setCsrfToken(session.csrf_token);
  }
  useEffect(() => {
    let active = true;
    initialSession.current ??= api<Session>("/session");
    initialSession.current
      .then((session) => {
        if (active) apply(session);
      })
      .catch(() => {
        if (active) setError("Не удалось подключиться к MESH. Обновите страницу.");
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, []);

  async function signOut() {
    apply(await api<Session>("/session", { method: "DELETE" }));
  }

  return (
    <Context.Provider value={{ account, loading, openLogin: () => setLogin(true), signOut }}>
      {children}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      {login && <LoginDialog onClose={() => setLogin(false)} onSignedIn={apply} />}
    </Context.Provider>
  );
}

export function useSession() {
  const context = useContext(Context);
  if (!context) throw new Error("SessionProvider is missing.");
  return context;
}

function LoginDialog({
  onClose,
  onSignedIn,
}: {
  onClose: () => void;
  onSignedIn: (session: Session) => void;
}) {
  const [register, setRegister] = useState(false);
  const [error, setError] = useState("");
  const [pending, setPending] = useState(false);

  async function submit(form: FormData) {
    setPending(true);
    setError("");
    const body = register
      ? {
          account: {
            email: form.get("email"),
            password: form.get("password"),
            display_name: form.get("display_name"),
            persona: form.get("persona"),
          },
        }
      : { session: { email: form.get("email"), password: form.get("password") } };
    try {
      onSignedIn(await api<Session>(register ? "/accounts" : "/session", { method: "POST", body }));
      onClose();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : "Не удалось войти.");
    } finally {
      setPending(false);
    }
  }

  return (
    <Modal title={register ? "Начать с MESH" : "С возвращением"} onClose={onClose}>
      <p className="muted">Ваша следующая хорошая работа начинается здесь.</p>
      <form action={submit} className="form-stack">
        {register && (
          <label>
            Имя
            <input name="display_name" required maxLength={80} autoComplete="name" />
          </label>
        )}
        <label>
          Email
          <input
            name="email"
            type="email"
            required
            autoComplete="email"
            defaultValue={register ? "" : "client@mesh.local"}
          />
        </label>
        <label>
          Пароль
          <input
            name="password"
            type="password"
            required
            minLength={12}
            autoComplete={register ? "new-password" : "current-password"}
            defaultValue={register ? "" : "MeshDemo2026!"}
          />
        </label>
        {register && (
          <label>
            Я здесь как
            <select name="persona">
              <option value="client">Заказчик</option>
              <option value="creator">Автор</option>
            </select>
          </label>
        )}
        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}
        <button className="button primary" disabled={pending}>
          {pending ? "Подождите…" : register ? "Создать аккаунт" : "Войти"}
        </button>
      </form>
      <button className="text-button" onClick={() => setRegister(!register)}>
        {register ? "Уже есть аккаунт? Войти" : "Создать аккаунт"}
      </button>
      {!register && (
        <div className="demo-note">
          Демо: client@mesh.local · creator@mesh.local · ops@mesh.local
          <br />
          Пароль: MeshDemo2026!
        </div>
      )}
    </Modal>
  );
}
