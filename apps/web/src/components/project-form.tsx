"use client";

import { useRouter } from "next/navigation";
import { categories, type Project } from "@/lib/api";
import { useCommand } from "@/lib/use-command";
import { Modal } from "./modal";

export function ProjectForm({
  onClose,
  project,
  onSaved,
}: {
  onClose: () => void;
  project?: Project;
  onSaved?: () => void;
}) {
  const router = useRouter();
  const command = useCommand();
  const scale = project?.currency === "JPY" ? 1 : 100;
  const lines = (form: FormData, field: string) =>
    String(form.get(field) ?? "")
      .split("\n")
      .map((item) => item.trim())
      .filter(Boolean);
  async function submit(form: FormData) {
    try {
      const result = await command.execute<Project>(
        project ? `/projects/${project.id}` : "/projects",
        {
          project: {
            title: form.get("title"),
            description: form.get("description"),
            category: form.get("category"),
            budget_minor: Math.round(Number(form.get("budget")) * scale),
            currency: project?.currency ?? "RUB",
            deadline: form.get("deadline"),
            expected_result: form.get("expected_result"),
            deliverables: lines(form, "deliverables"),
            requirements: lines(form, "requirements"),
            skills: String(form.get("skills") ?? "")
              .split(",")
              .map((item) => item.trim())
              .filter(Boolean),
            reference_urls: lines(form, "reference_urls"),
          },
          ...(project ? { version: project.lock_version } : {}),
        },
        project ? "PATCH" : "POST",
      );
      onClose();
      if (onSaved) onSaved();
      else router.push(`/projects/${result.id}`);
    } catch {}
  }
  return (
    <Modal title={project ? "Уточнить бриф" : "Давайте создадим что-то хорошее"} onClose={onClose}>
      <p className="muted">Понятный бриф — начало сильного результата.</p>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          void submit(new FormData(event.currentTarget));
        }}
        className="form-stack"
      >
        <label>
          Название проекта
          <input
            name="title"
            defaultValue={project?.title}
            required
            maxLength={160}
            placeholder="Например, айдентика для кофейни"
          />
        </label>
        <label>
          Что нужно сделать
          <textarea
            name="description"
            defaultValue={project?.description}
            required
            maxLength={10000}
            rows={5}
            placeholder="Задача, ожидаемый результат и критерии приёмки"
          />
        </label>
        <label>
          Направление
          <select name="category" defaultValue={project?.category}>
            {categories.slice(1).map((item) => (
              <option key={item}>{item}</option>
            ))}
          </select>
        </label>
        <div className="form-row">
          <label>
            Бюджет, {project && project.currency !== "RUB" ? project.currency : "₽"}
            <input
              type="number"
              name="budget"
              required
              min={1}
              max={1000000000}
              step={scale === 1 ? "1" : "0.01"}
              defaultValue={project ? project.budget_minor / scale : 50000}
            />
          </label>
          <label>
            Дедлайн
            <input
              name="deadline"
              defaultValue={project?.deadline}
              type="date"
              required
              min={new Date().toISOString().slice(0, 10)}
            />
          </label>
        </div>
        <details className="project-form-details" open={project ? true : undefined}>
          <summary>Дополнить бриф: результат, требования и материалы</summary>
          <div className="form-stack">
            <label>
              Ожидаемый результат
              <textarea
                name="expected_result"
                defaultValue={project?.expected_result}
                maxLength={3000}
                rows={3}
                placeholder="Что должно получиться и как вы оцените результат"
              />
            </label>
            <label>
              Список работ
              <textarea
                name="deliverables"
                defaultValue={project?.deliverables.join("\n")}
                rows={4}
                placeholder="Каждая работа — с новой строки. До 20 пунктов, по 500 символов."
              />
            </label>
            <label>
              Требования к автору
              <textarea
                name="requirements"
                defaultValue={project?.requirements.join("\n")}
                rows={3}
                placeholder="Каждое требование — с новой строки. До 20 пунктов, по 500 символов."
              />
            </label>
            <label>
              Навыки
              <input
                name="skills"
                defaultValue={project?.skills.join(", ")}
                placeholder="Брендинг, Типографика, Figma — через запятую, до 20 навыков"
              />
            </label>
            <label>
              Ссылки на материалы
              <textarea
                name="reference_urls"
                defaultValue={project?.reference_urls.join("\n")}
                rows={3}
                placeholder="Одна ссылка https:// на строку. До 10 публичных ссылок."
              />
            </label>
            <p className="small muted">
              Разместите файлы в своём хранилище и добавьте публичные ссылки. Эти поля сохраняются в
              версии брифа.
            </p>
          </div>
        </details>
        {command.error && (
          <p className="error" role="alert">
            {command.error}
          </p>
        )}
        <button className="button primary" disabled={command.pending}>
          {command.pending
            ? "Сохраняем…"
            : project
              ? "Сохранить новую версию"
              : "Опубликовать проект"}
        </button>
      </form>
    </Modal>
  );
}
