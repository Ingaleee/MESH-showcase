import Image from "next/image";
import Link from "next/link";
import { ArrowUpRight } from "lucide-react";
import { formatMoney, type Profile } from "@/lib/api";
import { imagePath } from "@/lib/home-content";
import { EditorialAvatar } from "./editorial-avatar";

const inspirations = [
  ["category-texts", "brand-still-life", "category-marketing"],
  ["category-design", "brand-still-life", "category-marketing"],
  ["category-video", "mountain-film", "hero-portrait"],
  ["category-development", "category-design", "category-marketing"],
];

export function HomeCreatorCard({ profile, index }: { profile: Profile; index: number }) {
  return (
    <Link
      className="home-creator-card"
      href={`/creators?profile=${encodeURIComponent(profile.id)}`}
      aria-label={`Познакомиться с автором ${profile.account.display_name}`}
    >
      <div className="home-creator-identity">
        <EditorialAvatar index={index} />
        <div>
          <h3>{profile.account.display_name}</h3>
          <p>{profile.headline}</p>
          <span className="home-creator-status">
            <i />
            Независимый автор
          </span>
        </div>
      </div>
      <div className="home-skill-tags">
        {profile.skills.slice(0, 3).map((skill) => (
          <span key={skill}>{skill}</span>
        ))}
      </div>
      <div className="home-creator-inspiration" aria-hidden="true">
        {inspirations[index % 4].map((image) => (
          <span key={image}>
            <Image src={imagePath(image)} alt="" fill sizes="100px" />
          </span>
        ))}
      </div>
      <div className="home-creator-rate">
        <strong>
          от {formatMoney(profile.rate_minor, profile.currency)}
          <small> / проект</small>
        </strong>
        <ArrowUpRight size={18} />
      </div>
    </Link>
  );
}
