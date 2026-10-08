"use client";

import { useState } from "react";
import Image from "next/image";
import { ArrowLeft, ArrowRight, Expand } from "lucide-react";
import type { Project } from "@/lib/api";
import { projectGallery } from "@/lib/project-content";
import { Modal } from "@/components/modal";

export function BriefGallery({ project }: { project: Project }) {
  const images = projectGallery(project);
  const [selected, setSelected] = useState<number | null>(null);
  return (
    <>
      <div className="project-gallery">
        {images.map((image, index) => (
          <button
            key={image.src}
            onClick={() => setSelected(index)}
            aria-label={`Увеличить иллюстрацию: ${image.title}`}
          >
            <Image src={image.src} alt={image.title} fill sizes="(max-width: 650px) 55vw, 260px" />
            <span>
              {image.title}
              <Expand size={16} />
            </span>
          </button>
        ))}
      </div>
      <p className="project-caption">
        Иллюстрации MESH для настроения проекта. Финальное направление вы обсудите с заказчиком.
      </p>
      {selected !== null && (
        <Modal
          title={images[selected].title}
          onClose={() => setSelected(null)}
          className="project-lightbox"
        >
          <div className="project-lightbox-image">
            <Image
              src={images[selected].src}
              alt={images[selected].title}
              fill
              sizes="(max-width: 700px) 90vw, 700px"
            />
          </div>
          {images.length > 1 && (
            <div className="project-lightbox-controls">
              <button
                className="icon-button"
                aria-label="Предыдущая иллюстрация"
                onClick={() => setSelected((selected + images.length - 1) % images.length)}
              >
                <ArrowLeft size={20} />
              </button>
              <span aria-live="polite">
                {selected + 1} / {images.length}
              </span>
              <button
                className="icon-button"
                aria-label="Следующая иллюстрация"
                onClick={() => setSelected((selected + 1) % images.length)}
              >
                <ArrowRight size={20} />
              </button>
            </div>
          )}
        </Modal>
      )}
    </>
  );
}
