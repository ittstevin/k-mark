"use client";

import Image from "next/image";
import Link from "next/link";
import type { Listing } from "../data/listings";

type ListingCardProps = {
  listing: Listing;
  isFavorite: boolean;
  onToggleFavorite: (id: string) => void;
};

export default function ListingCard({
  listing,
  isFavorite,
  onToggleFavorite,
}: ListingCardProps) {
  return (
    <article className="listing-card">
      <Link
        className="listing-card-link"
        href={`/listings/${listing.slug}`}
        aria-label={`View ${listing.title}`}
      >
        <div className="listing-image-wrap">
          <span className="image-fallback" aria-hidden="true">
            {listing.emoji}
          </span>
          <Image
            className="listing-image"
            src={listing.image}
            alt={listing.imageAlt}
            fill
            sizes="(max-width: 640px) 78vw, (max-width: 1000px) 42vw, 25vw"
            unoptimized
            onError={(event) => {
              event.currentTarget.style.opacity = "0";
            }}
          />
          {listing.featured && <span className="featured-label">Featured</span>}
        </div>
        <div className="listing-card-copy">
          <span className="listing-category">{listing.category}</span>
          <h3>{listing.title}</h3>
          <p className="listing-price">KSh {listing.price.toLocaleString("en-KE")}</p>
          <div className="listing-meta">
            <span>{listing.area}, {listing.county}</span>
            <span aria-hidden="true">·</span>
            <span>{listing.posted}</span>
          </div>
        </div>
      </Link>
      <button
        className={`favorite-button${isFavorite ? " is-favorite" : ""}`}
        type="button"
        aria-label={
          isFavorite
            ? `Remove ${listing.title} from favourites`
            : `Add ${listing.title} to favourites`
        }
        aria-pressed={isFavorite}
        onClick={() => onToggleFavorite(listing.id)}
      >
        <span aria-hidden="true">{isFavorite ? "♥" : "♡"}</span>
      </button>
    </article>
  );
}