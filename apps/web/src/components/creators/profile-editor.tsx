"use client";

import { Modal } from "@/components/modal";
import { useCommand } from "@/lib/use-command";
import type { Profile } from "@/lib/api";

export function CreatorProfileEditor({
  profile,
  onClose,
  onSaved,
}: {
  profile?: Profile;
  onClose: () => void;
  onSaved: () => void;
}) {
  const command = useCommand();

  async function save(form: FormData) {
    try {
      await command.execute("/creators", {
        profile: {
          headline: form.get("headline"),
          bio: form.get("bio"),
          skills: String(form.get("skills"))
            .split(",")
            .map((skill) => skill.trim())
            .filter(Boolean),
          rate_minor: Math.round(Number(form.get("rate")) * 100),
          currency: "RUB",
        },
      });
      onSaved();
    } catch {}
  }

  return (
    <Modal title="Ваше место в MESH" onClose={onClose}>
      <form className="form-stack" action={save}>
        <label>
          Специализация
          <input
            name="headline"
            required
            maxLength={160}
            defaultValue={profile?.headline}
            placeholder="Редактор, который делает сложное понятным"
          />
        </label>
        <label>
          О себе
          <textarea name="bio" rows={4} maxLength={5000} defaultValue={profile?.bio} />
        </label>
        <label>
          Навыки через запятую
          <input
            name="skills"
            defaultValue={profile?.skills.join(", ")}
            placeholder="Редактура, UX-тексты, интервью"
          />
        </label>
        <label>
          Ориентир за проект, ₽
          <input
            name="rate"
            type="number"
            min={0}
            step="0.01"
            defaultValue={(profile?.rate_minor ?? 3000000) / 100}
          />
        </label>
        {command.error && (
          <p className="error" role="alert">
            {command.error}
          </p>
        )}
        <button className="button primary" disabled={command.pending}>
          Сохранить профиль
        </button>
      </form>
    </Modal>
  );
}
