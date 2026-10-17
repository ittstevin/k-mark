import Link from "next/link";

type ComingSoonProps = {
  eyebrow: string;
  title: string;
  message: string;
};

export default function ComingSoon({ eyebrow, title, message }: ComingSoonProps) {
  return (
    <main className="placeholder-page">
      <div className="placeholder-panel">
        <Link className="brand" href="/" aria-label="K-Mark home">
          <span className="brand-mark" aria-hidden="true">K</span>
          <span className="brand-name">K-Mark</span>
        </Link>
        <p className="eyebrow placeholder-eyebrow">{eyebrow}</p>
        <h1>{title}</h1>
        <p className="placeholder-message">{message}</p>
        <Link className="button button-dark" href="/">Back to the marketplace <span aria-hidden="true">↗</span></Link>
        <p className="placeholder-tagline">Buy. Sell. Connect.</p>
      </div>
    </main>
  );
}