"use client";

type SearchControlsProps = {
  query: string;
  onQueryChange: (query: string) => void;
  location: string;
  onLocationChange: (location: string) => void;
};

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

export default function SearchControls({
  query,
  onQueryChange,
  location,
  onLocationChange,
}: SearchControlsProps) {
  function submitSearch(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    document.getElementById("listings")?.scrollIntoView({ behavior: "smooth" });
  }

  return (
    <form className="search-form" onSubmit={submitSearch} role="search">
      <label className="search-field">
        <span className="search-icon" aria-hidden="true">⌕</span>
        <span className="sr-only">Search listings</span>
        <input
          type="search"
          placeholder="What are you looking for?"
          value={query}
          onChange={(event) => onQueryChange(event.target.value)}
        />
        {query && (
          <button
            className="clear-search"
            type="button"
            aria-label="Clear search"
            onClick={() => onQueryChange("")}
          >
            ×
          </button>
        )}
      </label>
      <label className="location-field">
        <span className="location-icon" aria-hidden="true">⌖</span>
        <span className="sr-only">Filter by location</span>
        <select value={location} onChange={(event) => onLocationChange(event.target.value)}>
          {locations.map((place) => <option key={place}>{place}</option>)}
        </select>
      </label>
      <button className="search-submit" type="submit">Search</button>
    </form>
  );
}