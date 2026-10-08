import { ArrowUpRight, Check, FileText, Link2, Sparkles } from "lucide-react";
import type { Project, ProjectDetail } from "@/lib/api";
import { briefDate, briefFieldLabels } from "@/lib/project-content";
import { BriefGallery } from "./brief-gallery";

export function BriefContent({
  project,
  history,
}: {
  project: Project;
  history: ProjectDetail["brief_history"];
}) {
  return (
    <>
      <section id="project-about" className="project-section">
        <span className="project-section-kicker">01 / КОНТЕКСТ</span>
        <h2>Задача</h2>
        <p className="project-prose">{project.description}</p>
      </section>
      {project.deliverables.length > 0 && (
        <section className="project-section">
          <h2>Что нужно сделать</h2>
          <ul className="project-checklist">
            {project.deliverables.map((item, index) => (
              <li key={index}>
                <span>
                  <Check size={15} />
                </span>
                {item}
              </li>
            ))}
          </ul>
        </section>
      )}
      {project.expected_result && (
        <section className="project-section project-result">
          <Sparkles size={24} />
          <div>
            <h2>Ожидаемый результат</h2>
            <p className="project-prose">{project.expected_result}</p>
          </div>
        </section>
      )}
      <section id="project-requirements" className="project-section">
        <span className="project-section-kicker">02 / СОТРУДНИЧЕСТВО</span>
        <h2>Требования к автору</h2>
        {project.requirements.length ? (
          <ul className="project-requirement-list">
            {project.requirements.map((item, index) => (
              <li key={index}>
                <span>{String(index + 1).padStart(2, "0")}</span>
                {item}
              </li>
            ))}
          </ul>
        ) : (
          <p className="project-empty-copy">
            Отдельные требования пока не указаны. Опишите в предложении опыт, который поможет решить
            эту задачу.
          </p>
        )}
      </section>
      <section id="project-inspiration" className="project-section">
        <div className="project-section-heading">
          <div>
            <span className="project-section-kicker">03 / НАСТРОЕНИЕ</span>
            <h2>Визуальное направление</h2>
          </div>
          <span className="project-mini-label">MESH EDITORIAL</span>
        </div>
        <BriefGallery project={project} />
      </section>
      <section id="project-materials" className="project-section">
        <h2>Материалы от заказчика</h2>
        {project.reference_urls.length ? (
          <div className="project-materials">
            {project.reference_urls.map((url, index) => (
              <a href={url} key={`${url}-${index}`} target="_blank" rel="noopener noreferrer">
                <span className="project-file-icon">
                  <Link2 size={20} />
                </span>
                <div>
                  <strong>Материал {index + 1}</strong>
                  <span>{new URL(url).hostname}</span>
                </div>
                <ArrowUpRight size={19} />
              </a>
            ))}
          </div>
        ) : (
          <div className="project-material-empty">
            <FileText size={25} />
            <div>
              <strong>Пока без дополнительных материалов</strong>
              <p>
                Заказчик ещё не добавил ссылки на файлы и референсы. Всё, что нужно для первого
                предложения, — в брифе выше.
              </p>
            </div>
          </div>
        )}
      </section>
      <section id="project-history" className="project-section">
        <h2>История обновлений</h2>
        <ol className="project-timeline">
          {[...history].reverse().map((update) => (
            <li key={update.version}>
              <span className="project-timeline-dot" />
              <div>
                <span className="project-caption">
                  {briefDate(update.created_at)} · v{update.version}
                </span>
                <p>
                  {update.version === 1
                    ? "Проект опубликован"
                    : update.changed_fields.length
                      ? `Обновлены: ${update.changed_fields.map((field) => briefFieldLabels[field] ?? field).join(", ")}`
                      : "Сохранена новая версия брифа"}
                </p>
              </div>
            </li>
          ))}
        </ol>
        <p className="project-caption">
          История последних 50 версий. Каждое предложение связано со своей версией брифа.
        </p>
      </section>
    </>
  );
}
