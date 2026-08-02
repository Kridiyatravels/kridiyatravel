# Kridiya Travel & Tours Illustration System

This library uses a premium monoline editorial style for Kridiya’s website:

- thin charcoal-grey outlines
- mostly white and warm-cream interiors
- saffron orange and golden yellow as the primary accents
- deep brown for selective emphasis
- muted blue or green only as minor supporting accents
- spacious, calm compositions with simple geometric travel objects
- minimal, varied human characters
- no gradients, heavy shadows, blur, 3D, mascots, logos, watermarks, or embedded text

## Core palette

| Token | Value | Usage |
| --- | --- | --- |
| Line | `#5B554F` | Primary monoline stroke |
| Deep brown | `#4A3B31` | High-emphasis details |
| Saffron | `#F4A62A` | Main brand accent |
| Golden yellow | `#F6C85F` | Secondary accent |
| Warm cream | `#FFF6E7` | Soft object fill |
| Muted blue | `#8EBFD0` | Water and rare supporting cues |
| Muted green | `#9DB9A4` | Rare approval or nature cues |

## Wide hero scenes

All final hero PNGs are `1600×700` with an alpha channel.

| Page | File |
| --- | --- |
| Homepage | `heroes/homepage.png` |
| Flights | `heroes/flights.png` |
| Hotels | `heroes/hotels.png` |
| Holidays | `heroes/holidays.png` |
| Umrah | `heroes/umrah.png` |
| Cruise | `heroes/cruise.png` |
| Visa | `heroes/visa.png` |
| Business travel | `heroes/business-travel.png` |
| About | `heroes/about.png` |
| Contact | `heroes/contact.png` |
| Login/account | `heroes/account.png` |

The chroma-key source renders are retained in `heroes/source/` for controlled rebuilding.

## Mini spot objects

Each object ships as an editable transparent SVG and a matching transparent `512×512` PNG:

`boarding-pass`, `passport`, `suitcase`, `hotel-building`, `hotel-bed`,
`cruise-ship`, `visa-document`, `approved-stamp`, `route-map`,
`airplane-trail`, `camera`, `beach-hat`, `calendar`, `checklist`,
`support-headset`, `chat-bubble`, `destination-pin`, `laptop-ticket`,
`passport-folder`, and `secure-shield`.

SVG files live in `spots/svg/`. PNG files live in `spots/png/`.

## Web usage

For hero scenes, use `object-fit: contain` and preserve the `1600 / 700`
aspect ratio. Do not place the illustrations inside clipped circles or add
drop shadows. On dark surfaces, place them on a warm-cream panel so the
white interiors remain legible.

For spot objects, use the SVG files wherever possible. A typical visual size
is `72–160px`; use the PNG fallback only when the consuming system cannot
render SVG.

## Rebuild

Run:

```powershell
node .\scripts\build-illustrations.js
```

This regenerates all mini SVG/PNG pairs and rebuilds the transparent,
properly-sized hero PNGs from the retained source renders.
