import Image from "next/image";
import { imagePath } from "@/lib/home-content";

export function EditorialAvatar({
  index = 0,
  className = "",
  sizes = "240px",
}: {
  index?: number;
  className?: string;
  sizes?: string;
}) {
  return (
    <span className={`editorial-avatar ${className}`} aria-hidden="true">
      <Image
        src={imagePath("creator-portraits")}
        alt=""
        width={2172}
        height={724}
        sizes={sizes}
        style={{
          width: "400%",
          height: "100%",
          position: "absolute",
          top: 0,
          maxWidth: "none",
          left: `${(index % 4) * -100}%`,
          right: "auto",
          objectFit: "cover",
        }}
      />
    </span>
  );
}
