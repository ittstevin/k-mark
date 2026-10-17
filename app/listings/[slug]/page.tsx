import Link from "next/link";
import { notFound } from "next/navigation";
import DetailImage from "../../components/detail-image";
import { listings } from "../../data/listings";

export function generateStaticParams() {
  return listings.map((listing) => ({ slug: listing.slug }));
}

export default async function ListingPage({
  params,
}: PageProps<"/listings/[slug]">) {
  const { slug } = await params;
  const listing = listings.find((item) => item.slug === slug);

  if (!listing) notFound();

  return (
    <main className="detail-page">
      <div className="detail-topbar">
        <Link className="brand" href="/" aria-label="K-Mark home">
          <span className="brand-mark" aria-hidden="true">K</span>
          <span className="brand-name">K-Mark</span>
        </Link>
        <Link className="detail-back-link" href="/#listings">← Back to finds</Link>
      </div>
      <article className="detail-layout">
        <DetailImage src={listing.image} alt={listing.imageAlt} emoji={listing.emoji} />
        <div className="detail-copy">
          <p className="eyebrow">{listing.category} · {listing.county}</p>
          <h1>{listing.title}</h1>
          <p className="detail-price">KSh {listing.price.toLocaleString("en-KE")}</p>
          <p className="detail-location">⌖ &nbsp;{listing.area}, {listing.county}</p>
          <div className="detail-divider" />
          <h2>About this find</h2>
          <p className="detail-description">{listing.description}</p>
          <div className="seller-note">
            <span className="seller-avatar" aria-hidden="true">{listing.seller.charAt(0)}</span>
            <span><strong>{listing.seller}</strong><small>Fictional seller for demonstration</small></span>
          </div>
          <div className="detail-safety"><strong>Meet safely</strong><p>Meet in a public place, inspect the item first, and never pay before you are comfortable.</p></div>
          <Link className="button button-dark detail-action" href="/sign-in">Sign in to get started <span aria-hidden="true">↗</span></Link>
          <p className="detail-demo-note">Demo listing only. Contact and messaging are not available.</p>
        </div>
      </article>
    </main>
  );
}