import Link from "next/link";
import Brand from "./brand";

type ComingSoonProps = {
  eyebrow: string;
  title: string;
  message: string;
};

export default function ComingSoon({ eyebrow, title, message }: ComingSoonProps) {
  return (
    <main className="placeholder-page">
      <div className="placeholder-panel">
        <Brand />
        <p className="eyebrow placeholder-eyebrow">{eyebrow}</p>
        <h1>{title}</h1>
        <p className="placeholder-message">{message}</p>
        <Link className="button button-dark" href="/">Back to the marketplace <span aria-hidden="true">↗</span></Link>
        <p className="placeholder-tagline">Buy. Sell. Connect.</p>
      </div>
    </main>
  );
}