"use client";

import Image from "next/image";

type DetailImageProps = {
  src: string;
  alt: string;
  emoji: string;
};

export default function DetailImage({ src, alt, emoji }: DetailImageProps) {
  return (
    <div className="detail-image-wrap">
      <span className="detail-image-fallback" aria-hidden="true">{emoji}</span>
      <Image
        src={src}
        alt={alt}
        fill
        priority
        sizes="(max-width: 760px) 100vw, 58vw"
        unoptimized
        onError={(event) => {
          event.currentTarget.style.opacity = "0";
        }}
      />
    </div>
  );
}