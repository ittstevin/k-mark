import Link from "next/link";

type BrandProps = {
  className?: string;
};

export default function Brand({ className = "" }: BrandProps) {
  return (
    <Link
      className={`brand${className ? ` ${className}` : ""}`}
      href="/"
      aria-label="K-Mark home"
    >
      <span className="brand-mark" aria-hidden="true">K</span>
      <span className="brand-name">K-Mark</span>
    </Link>
  );
}