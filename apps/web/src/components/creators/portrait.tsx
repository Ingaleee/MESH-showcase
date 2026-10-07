import Image from "next/image";
import { EditorialAvatar } from "@/components/home/editorial-avatar";

export function CreatorPortrait({ index }: { index: number }) {
  if (index < 4)
    return <EditorialAvatar index={index} className="directory-portrait" sizes="480px" />;

  return (
    <span className="directory-portrait directory-extra-portrait" aria-hidden="true">
      <Image
        src="/images/creators/portrait-duo.png"
        alt=""
        width={1536}
        height={768}
        sizes="240px"
        style={{ width: "200%", height: "100%", left: `${((index - 4) % 2) * -100}%` }}
      />
    </span>
  );
}
