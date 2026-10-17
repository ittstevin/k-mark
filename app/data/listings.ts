export type ListingCategory =
  | "Electronics"
  | "Vehicles"
  | "Property"
  | "Fashion"
  | "Home & Living"
  | "Tools"
  | "Services";

export type Listing = {
  id: string;
  slug: string;
  title: string;
  price: number;
  area: string;
  county: "Nairobi" | "Kiambu";
  category: ListingCategory;
  description: string;
  image: string;
  imageAlt: string;
  emoji: string;
  posted: string;
  featured?: boolean;
  seller: string;
};

export const categoryOptions: { name: ListingCategory; icon: string }[] = [
  { name: "Electronics", icon: "⌁" },
  { name: "Vehicles", icon: "↗" },
  { name: "Property", icon: "⌂" },
  { name: "Fashion", icon: "✳" },
  { name: "Home & Living", icon: "▤" },
  { name: "Tools", icon: "⌘" },
  { name: "Services", icon: "＋" },
];

export const listings: Listing[] = [
  {
    id: "camera-01",
    slug: "canon-eos-200d-ii",
    title: "Canon EOS 200D II, lightly used",
    price: 56000,
    area: "Westlands",
    county: "Nairobi",
    category: "Electronics",
    description:
      "A compact, easy-to-carry camera with a flip screen. Includes the standard lens, one battery and a carry pouch. A fictional demonstration listing.",
    image:
      "https://images.unsplash.com/photo-1516035069371-29a1b244cc32?auto=format&fit=crop&w=1000&q=85",
    imageAlt: "Black digital camera with a lens attached",
    emoji: "📷",
    posted: "Today",
    featured: true,
    seller: "Demo seller, Westlands",
  },
  {
    id: "sofa-01",
    slug: "olive-green-two-seater-sofa",
    title: "Olive green two-seater sofa",
    price: 38500,
    area: "Kilimani",
    county: "Nairobi",
    category: "Home & Living",
    description:
      "A comfortable two-seater in good condition, with removable cushion covers. Pickup can be arranged in Kilimani. Fictional demo listing.",
    image:
      "https://images.unsplash.com/photo-1555041469-a586c61ea9bc?auto=format&fit=crop&w=1000&q=85",
    imageAlt: "Green sofa in a bright, modern living room",
    emoji: "🛋️",
    posted: "Today",
    featured: true,
    seller: "Demo seller, Kilimani",
  },
  {
    id: "phone-01",
    slug: "samsung-galaxy-a55-128gb",
    title: "Samsung Galaxy A55, 128 GB",
    price: 42500,
    area: "Kasarani",
    county: "Nairobi",
    category: "Electronics",
    description:
      "Unlocked 128 GB phone in very good condition. Comes with its box and charging cable. Fictional demo listing.",
    image:
      "https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?auto=format&fit=crop&w=1000&q=85",
    imageAlt: "Modern smartphone viewed from the back",
    emoji: "📱",
    posted: "Yesterday",
    featured: true,
    seller: "Demo seller, Kasarani",
  },
  {
    id: "dining-01",
    slug: "solid-wood-dining-set-six-seater",
    title: "Solid wood dining set, six-seater",
    price: 47000,
    area: "Kiambu Town",
    county: "Kiambu",
    category: "Home & Living",
    description:
      "A sturdy dining table with six matching chairs. Light signs of use; collection in Kiambu Town. Fictional demo listing.",
    image:
      "https://images.unsplash.com/photo-1617806118233-18e1de247200?auto=format&fit=crop&w=1000&q=85",
    imageAlt: "Wood dining table and chairs in a home",
    emoji: "🪑",
    posted: "Yesterday",
    featured: true,
    seller: "Demo seller, Kiambu Town",
  },
  {
    id: "car-01",
    slug: "toyota-vitz-2017-clean-condition",
    title: "Toyota Vitz 2017, clean condition",
    price: 1280000,
    area: "Ruiru",
    county: "Kiambu",
    category: "Vehicles",
    description:
      "A tidy, locally used hatchback with a 1.0L engine. Viewing by appointment in Ruiru. Fictional demo listing; details are illustrative only.",
    image:
      "https://images.unsplash.com/photo-1492144534655-ae79c964c9d7?auto=format&fit=crop&w=1000&q=85",
    imageAlt: "Silver compact car parked outdoors",
    emoji: "🚗",
    posted: "2 days ago",
    seller: "Demo seller, Ruiru",
  },
  {
    id: "rental-01",
    slug: "two-bedroom-apartment-thika-road",
    title: "Bright 2-bedroom apartment near Thika Road",
    price: 48000,
    area: "Roysambu",
    county: "Nairobi",
    category: "Property",
    description:
      "Two bedrooms, a balcony and easy access to the main road. Rent shown per month. Visit in person before making any payment. Fictional demo listing.",
    image:
      "https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?auto=format&fit=crop&w=1000&q=85",
    imageAlt: "Sunlit apartment building with a green garden",
    emoji: "🏡",
    posted: "2 days ago",
    seller: "Demo seller, Roysambu",
  },
  {
    id: "jacket-01",
    slug: "denim-jacket-medium",
    title: "Classic denim jacket, size M",
    price: 2800,
    area: "Kikuyu",
    county: "Kiambu",
    category: "Fashion",
    description:
      "A classic blue denim jacket in great condition. Available for a local meetup in Kikuyu. Fictional demo listing.",
    image:
      "https://images.unsplash.com/photo-1543076447-215ad9ba6923?auto=format&fit=crop&w=1000&q=85",
    imageAlt: "Blue denim jacket on a clothing rack",
    emoji: "🧥",
    posted: "3 days ago",
    seller: "Demo seller, Kikuyu",
  },
  {
    id: "drill-01",
    slug: "cordless-drill-and-bit-set",
    title: "Cordless drill with bit set",
    price: 8900,
    area: "Thika",
    county: "Kiambu",
    category: "Tools",
    description:
      "Cordless drill with charger, battery and a small set of bits. Tested and working. Fictional demo listing.",
    image:
      "https://images.unsplash.com/photo-1504148455328-c376907d081c?auto=format&fit=crop&w=1000&q=85",
    imageAlt: "Hand tools arranged on a workbench",
    emoji: "🛠️",
    posted: "3 days ago",
    seller: "Demo seller, Thika",
  },
  {
    id: "cleaning-01",
    slug: "home-cleaning-session-roy-sambu",
    title: "Home cleaning session, 2 hours",
    price: 2500,
    area: "Roysambu",
    county: "Nairobi",
    category: "Services",
    description:
      "A two-hour home cleaning session for a small apartment. Arrange the details directly before booking. Fictional demo listing.",
    image:
      "https://images.unsplash.com/photo-1581578731548-c64695cc6952?auto=format&fit=crop&w=1000&q=85",
    imageAlt: "Cleaning supplies arranged on a counter",
    emoji: "🧹",
    posted: "Today",
    seller: "Demo service provider, Roysambu",
  },
];