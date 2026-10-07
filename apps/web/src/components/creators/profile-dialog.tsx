import Image from "next/image";
import { ArrowRight, Bookmark } from "lucide-react";
import { Modal } from "@/components/modal";
import { formatMoney, type Profile } from "@/lib/api";
import { creatorDirection, creatorVisuals } from "@/lib/creator-content";
import { imagePath } from "@/lib/home-content";
import { CreatorPortrait } from "./portrait";

export function CreatorProfileDialog({
  profile,
  index,
  saved,
  onSave,
  onClose,
  onCreateProject,
}: {
  profile: Profile;
  index: number;
  saved: boolean;
  onSave: () => void;
  onClose: () => void;
  onCreateProject: () => void;
}) {
  return (
    <Modal
      title={profile.account.display_name}
      className="directory-profile-modal"
      onClose={onClose}
    >
      <div className="directory-profile-identity">
        <CreatorPortrait index={index} />
        <div>
          <span className="directory-direction">
            {creatorDirection(profile) ?? "Независимый автор"}
          </span>
          <h3>{profile.headline}</h3>
          <strong>
            от {formatMoney(profile.rate_minor, profile.currency)} <small>за проект</small>
          </strong>
        </div>
      </div>
      <div className="directory-skills">
        {profile.skills.map((skill) => (
          <span key={skill}>{skill}</span>
        ))}
      </div>
      <section className="directory-profile-about">
        <h3>Подход к работе</h3>
        <p>{profile.bio || "Расскажите о своей задаче, чтобы обсудить подход с автором."}</p>
      </section>
      <section>
        <h3 className="directory-profile-section-title">Визуальное направление</h3>
        <div className="directory-profile-visuals">
          {creatorVisuals(profile).map((visual) => (
            <span key={visual}>
              <Image
                src={imagePath(visual)}
                alt="Иллюстрация творческого направления"
                fill
                sizes="(max-width: 700px) 30vw, 240px"
              />
            </span>
          ))}
        </div>
        <p className="directory-demo-note">
          Демо-портрет и иллюстрации созданы для оформления MESH. Собственные работы автора появятся
          после загрузки портфолио.
        </p>
      </section>
      <div className="directory-profile-actions">
        <button className="mesh-button mesh-button-dark" onClick={onCreateProject}>
          Создать проект <ArrowRight size={18} />
        </button>
        <button className="mesh-button mesh-button-light" aria-pressed={saved} onClick={onSave}>
          <Bookmark size={17} fill={saved ? "currentColor" : "none"} />
          {saved ? "Автор сохранён" : "Сохранить автора"}
        </button>
      </div>
      <p className="directory-demo-note">
        Проект будет опубликован на площадке. Автор сможет предложить свой подход и стоимость.
      </p>
    </Modal>
  );
}
