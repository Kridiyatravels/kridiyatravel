# Kridiya Travel & Tours Illustration System — V2

Production-ready website illustration library matching the approved warm
Kridiya travel direction.

## Style tokens

| Token | Value |
| --- | --- |
| Saffron orange | `#F2820C` |
| Golden yellow | `#F6C445` |
| Warm cream | `#FFF6E7` |
| Deep brown | `#4A3B31` |
| Graphite outline | `#5B554F` |
| Muted blue accent | `#8EBFD0` |
| Muted green accent | `#9DB9A4` |

The system uses thin rounded graphite lines, mostly white or cream interiors,
small warm-color fills, clean geometric travel objects, varied minimal human
characters, and generous negative space. It contains no readable text, logos,
watermarks, gradients, heavy shadows, 3D objects, mascots, dark backgrounds,
or green backgrounds.

## Wide hero PNGs

All files in `heroes/` are transparent `1600×700` PNGs:

- `homepage.png`
- `flights.png`
- `hotels.png`
- `holidays.png`
- `umrah.png`
- `cruise.png`
- `visa.png`
- `business-travel.png`
- `about.png`
- `contact.png`
- `account.png`

## Mini spot objects

The complete 20-object set is available as editable SVG in `spots/svg/` and
transparent `512×512` PNG in `spots/png/`:

- boarding pass
- passport
- suitcase
- hotel building
- hotel bed
- cruise ship
- visa document
- approved stamp
- route map
- airplane trail
- camera
- beach hat
- calendar
- checklist
- support headset
- chat bubble
- destination pin
- laptop with ticket
- passport folder
- secure shield

## Recommended use

Use hero files with `object-fit: contain` and preserve their `1600 / 700`
aspect ratio. Use the SVG spot objects wherever possible; their ideal displayed
size is approximately `72–160px`. Do not add drop shadows, colored background
discs, or clipped icon containers.

## Rebuild

```powershell
node .\scripts\build-illustrations.js --v2
```

