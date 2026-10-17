"use client";

import Image from "next/image";
import Link from "next/link";
import { useState, useSyncExternalStore } from "react";
import ListingCard from "./listing-card";
import { categoryOptions, listings } from "../data/listings";
import type { ListingCategory } from "../data/listings";

type CategoryFilter = ListingCategory | "All categories";

const locations = [
  "All locations",
  "Nairobi",
  "Kiambu",
  "Westlands",
  "Kilimani",
  "Kasarani",
  "Roysambu",
  "Thika",
  "Ruiru",
  "Kiambu Town",
  "Kikuyu",
];

const emptyFavorites: string[] = [];
let favoriteSnapshot: string[] | null = null;
const favoriteListeners = new Set<() => void>();

function subscribeToFavorites(listener: () => void) {
  favoriteListeners.add(listener);
  return () => favoriteListeners.delete(listener);
}

function getFavoriteSnapshot() {
  if (favoriteSnapshot !== null) return favoriteSnapshot;

  try {
    const storedFavorites = window.sessionStorage.getItem("k-mark:favorites");
    const parsedFavorites: unknown = storedFavorites ? JSON.parse(storedFavorites) : [];
    favoriteSnapshot = Array.isArray(parsedFavorites)
      ? parsedFavorites.filter(
          (id): id is string =>
            typeof id === "string" && listings.some((listing) => listing.id === id),
        )
      : emptyFavorites;
  } catch {
    window.sessionStorage.removeItem("k-mark:favorites");
    favoriteSnapshot = emptyFavorites;
  }

  return favoriteSnapshot;
}

function saveFavoriteSnapshot(nextFavorites: string[]) {
  favoriteSnapshot = nextFavorites;
  window.sessionStorage.setItem("k-mark:favorites", JSON.stringify(nextFavorites));
  favoriteListeners.forEach((listener) => listener());
}

export default function Marketplace() {
  const [query, setQuery] = useState("");
  const [location, setLocation] = useState("All locations");
  const [category, setCategory] = useState<CategoryFilter>("All categories");
  const favorites = useSyncExternalStore(
    subscribeToFavorites,
    getFavoriteSnapshot,
    () => emptyFavorites,
  );

  const normalizedQuery = query.trim().toLowerCase();
  const visibleListings = listings.filter((listing) => {
    const matchesQuery =
      !normalizedQuery ||
      `${listing.title} ${listing.category} ${listing.area} ${listing.county} ${listing.description}`
        .toLowerCase()
        .includes(normalizedQuery);
    const matchesLocation =
      location === "All locations" ||
      listing.area === location ||
      listing.county === location;
    const matchesCategory =
      category === "All categories" || listing.category === category;

    return matchesQuery && matchesLocation && matchesCategory;
  });

  const featuredListings = visibleListings.filter((listing) => listing.featured);
  const recentListings = visibleListings.filter((listing) => !listing.featured);

  function toggleFavorite(id: string) {
    const nextFavorites = favorites.includes(id)
      ? favorites.filter((favoriteId) => favoriteId !== id)
      : [...favorites, id];

    saveFavoriteSnapshot(nextFavorites);
  }

  function selectCategory(nextCategory: CategoryFilter) {
    setCategory(nextCategory);
    document.getElementById("listings")?.scrollIntoView({ behavior: "smooth" });
  }

  function renderListingGrid(items: typeof visibleListings) {
    return (
      <div className="listing-grid">
        {items.map((listing) => (
          <ListingCard
            key={listing.id}
            listing={listing}
            isFavorite={favorites.includes(listing.id)}
            onToggleFavorite={toggleFavorite}
          />
        ))}
      </div>
    );
  }

  return (
    <>
      <header className="site-header">
        <div className="header-inner">
          <Link className="brand" href="/" aria-label="K-Mark home">
            <span className="brand-mark" aria-hidden="true">K</span>
            <span className="brand-name">K-Mark</span>
          </Link>
          <nav className="main-nav" aria-label="Main navigation">
            <Link href="/#categories">Explore</Link>
            <Link href="/#listings">Marketplace</Link>
            <Link href="/#safety">How it works</Link>
          </nav>
          <div className="header-actions">
            <Link className="sign-in-link" href="/sign-in">Sign in</Link>
            <Link className="button button-dark button-small" href="/sell">
              <span aria-hidden="true">＋</span> Sell an item
            </Link>
          </div>
        </div>
      </header>

      <main>
        <section className="hero-section">
          <div className="hero-inner">
            <div className="hero-copy">
              <p className="eyebrow"><span /> YOUR NEIGHBOURHOOD MARKETPLACE</p>
              <h1>Good finds.<br /><em>Closer to home.</em></h1>
              <p className="hero-description">
                Buy and sell pre-loved finds, everyday essentials and more around Nairobi and Kiambu.
              </p>
              <form className="search-form" onSubmit={(event) => event.preventDefault()}>
                <label className="search-field">
                  <span className="search-icon" aria-hidden="true">⌕</span>
                  <span className="sr-only">Search listings</span>
                  <input
                    type="search"
                    placeholder="What are you looking for?"
                    value={query}
                    onChange={(event) => setQuery(event.target.value)}
                  />
                  {query && (
                    <button
                      className="clear-search"
                      type="button"
                      aria-label="Clear search"
                      onClick={() => setQuery("")}
                    >
                      ×
                    </button>
                  )}
                </label>
                <label className="location-field">
                  <span className="location-icon" aria-hidden="true">⌖</span>
                  <span className="sr-only">Filter by location</span>
                  <select value={location} onChange={(event) => setLocation(event.target.value)}>
                    {locations.map((place) => <option key={place}>{place}</option>)}
                  </select>
                </label>
                <button className="search-submit" type="submit" aria-label="Search listings">
                  Search
                </button>
              </form>
              <p className="search-note">A better way to find what you need, right around the corner.</p>
            </div>
            <div className="hero-visual">
              <Image
                className="hero-image"
                src="https://images.unsplash.com/photo-1555041469-a586c61ea9bc?auto=format&fit=crop&w=1400&q=90"
                alt="A welcoming living room with a green sofa"
                fill
                priority
                sizes="(max-width: 800px) 100vw, 50vw"
                unoptimized
              />
              <div className="hero-image-shade" />
              <div className="hero-photo-caption">
                <span className="caption-kicker">GOOD THINGS, NEARBY</span>
                <span>Buy. Sell. Connect.</span>
              </div>
              <div className="hero-note">
                <span className="hero-note-icon" aria-hidden="true">↗</span>
                <span><strong>Made for local finds</strong><small>Nairobi & Kiambu, Kenya</small></span>
              </div>
            </div>
          </div>
          <div className="hero-bottomline"><span>01 / 07</span><span>NEAR YOU, EVERY DAY</span></div>
        </section>

        <section className="category-section page-section" id="categories" aria-labelledby="category-title">
          <div className="section-heading category-heading">
            <div>
              <p className="eyebrow">A LITTLE BIT OF EVERYTHING</p>
              <h2 id="category-title">What are you looking for?</h2>
            </div>
            <button className="text-link" type="button" onClick={() => selectCategory("All categories")}>
              Browse everything <span aria-hidden="true">↗</span>
            </button>
          </div>
          <div className="category-grid">
            {categoryOptions.map((item, index) => (
              <button
                key={item.name}
                className={`category-tile category-tone-${index + 1}${category === item.name ? " is-selected" : ""}`}
                type="button"
                aria-pressed={category === item.name}
                onClick={() => selectCategory(category === item.name ? "All categories" : item.name)}
              >
                <span className="category-icon" aria-hidden="true">{item.icon}</span>
                <span>{item.name}</span>
                <span className="category-arrow" aria-hidden="true">↗</span>
              </button>
            ))}
          </div>
        </section>

        <section className="listings-section page-section" id="listings" aria-labelledby="listings-title">
          <div className="section-heading listings-heading">
            <div>
              <p className="eyebrow">THE GOOD STUFF, CLOSE BY</p>
              <h2 id="listings-title">A few good finds</h2>
            </div>
            <span className="result-count">{visibleListings.length} local finds</span>
          </div>

          {(category !== "All categories" || location !== "All locations" || query) && (
            <div className="active-filters" aria-live="polite">
              <span>Showing {category !== "All categories" ? category : "all categories"}
                {location !== "All locations" ? ` in ${location}` : ""}
                {query ? ` matching “${query}”` : ""}
              </span>
              <button
                type="button"
                onClick={() => { setCategory("All categories"); setLocation("All locations"); setQuery(""); }}
              >
                Clear filters <span aria-hidden="true">×</span>
              </button>
            </div>
          )}

          {visibleListings.length === 0 ? (
            <div className="empty-state" role="status">
              <span className="empty-icon" aria-hidden="true">⌕</span>
              <h3>No finds this time</h3>
              <p>Try another search or widen your location to see more nearby listings.</p>
              <button
                className="button button-dark"
                type="button"
                onClick={() => { setCategory("All categories"); setLocation("All locations"); setQuery(""); }}
              >
                Clear filters
              </button>
            </div>
          ) : (
            <>
              {featuredListings.length > 0 && (
                <div className="listing-group">
                  <div className="listing-group-heading"><h3>Picked for you</h3><span>Good finds worth a look</span></div>
                  {renderListingGrid(featuredListings)}
                </div>
              )}
              {recentListings.length > 0 && (
                <div className="listing-group recent-group">
                  <div className="listing-group-heading"><h3>Recently added</h3><span>Fresh from around the neighbourhood</span></div>
                  {renderListingGrid(recentListings)}
                </div>
              )}
            </>
          )}
        </section>

        <section className="safety-section" id="safety" aria-labelledby="safety-title">
          <div className="safety-inner">
            <div className="safety-intro">
              <p className="eyebrow">A LITTLE CARE GOES A LONG WAY</p>
              <h2 id="safety-title">Good deals start with good sense.</h2>
              <p>K-Mark is a place to discover local listings. Take a moment to get to know an item and the person selling it.</p>
            </div>
            <div className="safety-tips">
              <article className="safety-tip"><span>01</span><div><h3>Meet somewhere public</h3><p>Choose a familiar, busy place for an in-person handover.</p></div></article>
              <article className="safety-tip"><span>02</span><div><h3>See it before you pay</h3><p>Inspect the item and agree on the details together.</p></div></article>
              <article className="safety-tip"><span>03</span><div><h3>Trust your instincts</h3><p>Take your time. If something feels off, walk away.</p></div></article>
            </div>
          </div>
        </section>
      </main>

      <footer className="site-footer">
        <div className="footer-main">
          <div className="footer-brand-block">
            <Link className="brand footer-brand" href="/">
              <span className="brand-mark" aria-hidden="true">K</span><span className="brand-name">K-Mark</span>
            </Link>
            <p>Buy. Sell. Connect.<br />Good finds, closer to home.</p>
          </div>
          <div className="footer-column"><h2>Discover</h2><Link href="/#categories">Browse categories</Link><Link href="/#listings">Recent finds</Link><Link href="/sell">Sell an item</Link></div>
          <div className="footer-column"><h2>Good to know</h2><Link href="/#safety">Stay safe</Link><Link href="/sign-in">Your account</Link><Link href="/help">Help & support</Link></div>
          <div className="footer-note"><span>MADE FOR THE NEIGHBOURHOOD</span><p>From Nairobi to Kiambu, a little closer to what you need.</p></div>
        </div>
        <div className="footer-bottom"><span>K-Mark · Demo marketplace</span><span>Every listing on this page is fictional.</span></div>
      </footer>
    </>
  );
}