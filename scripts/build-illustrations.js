const fs = require("node:fs");
const path = require("node:path");
const sharp = require("sharp");

const root = path.resolve(__dirname, "..");
const isV2 = process.argv.includes("--v2");
const libraryDir = path.join(root, "assets", isV2 ? "illustrations-v2" : "illustrations");
const heroSourceDir = isV2
  ? path.join(root, "assets", "illustrations", "heroes")
  : path.join(root, "assets", "illustrations", "heroes", "source");
const heroOutputDir = path.join(libraryDir, "heroes");
const spotSvgDir = path.join(libraryDir, "spots", "svg");
const spotPngDir = path.join(libraryDir, "spots", "png");

for (const dir of [heroOutputDir, spotSvgDir, spotPngDir]) {
  fs.mkdirSync(dir, { recursive: true });
}

const C = {
  line: "#5B554F",
  brown: "#4A3B31",
  orange: isV2 ? "#F2820C" : "#F4A62A",
  gold: isV2 ? "#F6C445" : "#F6C85F",
  cream: "#FFF6E7",
  blue: "#8EBFD0",
  green: "#9DB9A4",
  white: "#FFFFFF",
};

const svg = (body) => `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512" fill="none">
  <g stroke="${C.line}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">
    ${body}
  </g>
</svg>
`;

const icons = {
  "boarding-pass": `
    <path fill="${C.cream}" d="M78 156c0-22 18-40 40-40h276c22 0 40 18 40 40v42c-28 0-28 44 0 44v114c0 22-18 40-40 40H118c-22 0-40-18-40-40V242c28 0 28-44 0-44v-42Z"/>
    <path d="M310 118v278" stroke-dasharray="10 15"/>
    <path fill="${C.orange}" d="m170 269 72-40 12 13-53 53 34 55-18 10-48-47-45 22-12-12 58-54Z"/>
    <path d="M111 167h136M111 191h92M341 174h58M341 199h58M341 224h58"/>
  `,
  passport: `
    <rect x="116" y="72" width="280" height="368" rx="30" fill="${C.brown}"/>
    <path d="M154 72v368" stroke="${C.gold}"/>
    <circle cx="272" cy="238" r="73" stroke="${C.gold}"/>
    <path d="M199 238h146M272 165c22 23 34 47 34 73s-12 50-34 73c-22-23-34-47-34-73s12-50 34-73Z" stroke="${C.gold}"/>
    <path d="M222 354h100" stroke="${C.gold}"/>
  `,
  suitcase: `
    <path d="M196 119V86c0-18 14-32 32-32h56c18 0 32 14 32 32v33" />
    <rect x="92" y="116" width="328" height="304" rx="42" fill="${C.cream}"/>
    <path d="M150 116v304M362 116v304" stroke="${C.orange}"/>
    <rect x="218" y="168" width="76" height="28" rx="14" fill="${C.orange}"/>
    <circle cx="158" cy="448" r="16" fill="${C.brown}"/><circle cx="354" cy="448" r="16" fill="${C.brown}"/>
  `,
  "hotel-building": `
    <path fill="${C.cream}" d="M100 432V150l156-82 156 82v282H100Z"/>
    <path fill="${C.gold}" d="M82 150 256 54l174 96-18 34-156-86-156 86-18-34Z"/>
    <path d="M142 210h58v58h-58zM227 210h58v58h-58zM312 210h58v58h-58zM142 300h58v58h-58zM312 300h58v58h-58z"/>
    <path fill="${C.orange}" d="M224 432V310h64v122"/>
  `,
  "hotel-bed": `
    <path fill="${C.cream}" d="M82 214h348v174H82z"/>
    <path fill="${C.gold}" d="M84 308h344v80H84z"/>
    <path d="M82 388v54M430 388v54M82 214v-78h30c22 0 40 18 40 40v38"/>
    <path fill="${C.white}" d="M152 184h120c28 0 50 22 50 50v30H152v-80ZM322 184h42c36 0 66 30 66 66v14H322v-80Z"/>
  `,
  "cruise-ship": `
    <path fill="${C.cream}" d="M62 304h388l-57 100H134L62 304Z"/>
    <path fill="${C.white}" d="M130 226h252l34 78H96l34-78Z"/>
    <path fill="${C.gold}" d="M190 154h132v72H190z"/>
    <path d="M226 154v-50h60v50M114 338h284"/>
    <circle cx="166" cy="268" r="12"/><circle cx="216" cy="268" r="12"/><circle cx="266" cy="268" r="12"/><circle cx="316" cy="268" r="12"/><circle cx="366" cy="268" r="12"/>
    <path d="M54 438c38-24 66 24 104 0s66 24 104 0 66 24 104 0 66 24 104 0" stroke="${C.blue}"/>
  `,
  "visa-document": `
    <path fill="${C.cream}" d="M116 62h212l68 68v320H116V62Z"/>
    <path fill="${C.gold}" d="M328 62v68h68"/>
    <circle cx="202" cy="218" r="48" fill="${C.orange}"/>
    <path d="M278 190h72M278 220h72M156 298h196M156 334h196M156 370h126"/>
    <path d="m295 404 26 26 54-70" stroke="${C.green}" stroke-width="12"/>
  `,
  "approved-stamp": `
    <path fill="${C.cream}" d="M180 88c0-28 22-50 50-50h52c28 0 50 22 50 50v82c0 40 20 58 50 84H130c30-26 50-44 50-84V88Z"/>
    <path fill="${C.brown}" d="M116 254h280v58H116z"/>
    <rect x="88" y="312" width="336" height="104" rx="22" fill="${C.gold}"/>
    <path d="m176 363 46 38 112-112" stroke="${C.green}" stroke-width="15"/>
  `,
  "route-map": `
    <path fill="${C.cream}" d="m66 128 124-54 132 46 124-54v318l-124 54-132-46-124 54V128Z"/>
    <path d="M190 74v318M322 120v318"/>
    <path d="M112 330c72-124 114 56 190-58s102-30 102-30" stroke="${C.orange}" stroke-dasharray="13 16"/>
    <path fill="${C.orange}" d="M97 282c0-30 24-54 54-54s54 24 54 54c0 42-54 94-54 94s-54-52-54-94Z"/><circle cx="151" cy="282" r="17" fill="${C.white}"/>
    <path fill="${C.gold}" d="M334 176c0-25 20-45 45-45s45 20 45 45c0 35-45 78-45 78s-45-43-45-78Z"/><circle cx="379" cy="176" r="14" fill="${C.white}"/>
  `,
  "airplane-trail": `
    <path d="M68 380c64-120 124 48 204-78 50-78 106-38 154-112" stroke="${C.orange}" stroke-dasharray="14 18"/>
    <path fill="${C.cream}" d="m276 215 130-123 35 14-86 137 70 42-13 25-92-28-66 72-24-12 46-127Z"/>
  `,
  camera: `
    <path fill="${C.cream}" d="M72 172h90l28-48h132l28 48h90v244H72V172Z"/>
    <circle cx="256" cy="294" r="88" fill="${C.white}"/><circle cx="256" cy="294" r="56" fill="${C.blue}"/>
    <rect x="106" y="208" width="58" height="34" rx="12" fill="${C.orange}"/>
    <path d="M338 122h50v50"/>
  `,
  "beach-hat": `
    <ellipse cx="256" cy="352" rx="202" ry="70" fill="${C.cream}"/>
    <path fill="${C.gold}" d="M152 330c8-136 46-214 104-214s96 78 104 214H152Z"/>
    <path d="M164 278h184" stroke="${C.orange}" stroke-width="22"/>
    <path d="M348 278c42 12 62 44 80 77" stroke="${C.orange}"/>
  `,
  calendar: `
    <rect x="76" y="102" width="360" height="340" rx="30" fill="${C.cream}"/>
    <path fill="${C.gold}" d="M76 102h360v92H76z"/>
    <path d="M160 70v70M352 70v70"/>
    <path d="M132 244h48v48h-48zM232 244h48v48h-48zM332 244h48v48h-48zM132 338h48v48h-48zM232 338h48v48h-48z"/>
    <path fill="${C.orange}" d="M332 338h48v48h-48z"/>
  `,
  checklist: `
    <rect x="104" y="62" width="304" height="388" rx="28" fill="${C.cream}"/>
    <path fill="${C.gold}" d="M208 44h96v58h-96z"/>
    <path d="M154 170h46v46h-46zM154 260h46v46h-46zM154 350h46v46h-46zM236 190h118M236 280h118M236 370h118"/>
    <path d="m158 280 18 18 38-54M158 190l18 18 38-54" stroke="${C.green}" stroke-width="11"/>
  `,
  "support-headset": `
    <path d="M112 280v-50c0-86 64-156 144-156s144 70 144 156v50"/>
    <rect x="76" y="242" width="84" height="132" rx="34" fill="${C.gold}"/>
    <rect x="352" y="242" width="84" height="132" rx="34" fill="${C.gold}"/>
    <path d="M394 374c0 48-38 74-94 74h-28"/>
    <rect x="226" y="422" width="80" height="38" rx="19" fill="${C.orange}"/>
    <path d="M170 222c24-42 52-62 86-62s62 20 86 62"/>
  `,
  "chat-bubble": `
    <path fill="${C.cream}" d="M62 106c0-30 24-54 54-54h280c30 0 54 24 54 54v196c0 30-24 54-54 54H236l-96 92 16-92h-40c-30 0-54-24-54-54V106Z"/>
    <circle cx="170" cy="206" r="18" fill="${C.orange}" stroke="none"/><circle cx="256" cy="206" r="18" fill="${C.gold}" stroke="none"/><circle cx="342" cy="206" r="18" fill="${C.orange}" stroke="none"/>
  `,
  "destination-pin": `
    <path fill="${C.orange}" d="M256 50c-92 0-166 74-166 166 0 126 166 246 166 246s166-120 166-246c0-92-74-166-166-166Z"/>
    <circle cx="256" cy="216" r="68" fill="${C.cream}"/>
    <path d="M206 216h100M256 166c26 28 38 44 38 50s-12 22-38 50c-26-28-38-44-38-50s12-22 38-50Z"/>
  `,
  "laptop-ticket": `
    <path fill="${C.cream}" d="M98 90h316v230H98z"/>
    <path d="M58 358h396l-30 60H88l-30-60Z" fill="${C.white}"/>
    <path fill="${C.gold}" d="M160 154h192v110H160z"/>
    <path d="M256 154v110" stroke-dasharray="9 12"/>
    <path fill="${C.orange}" d="m212 210 45-29 11 10-30 32 25 25-12 10-34-22-26 15-9-9 30-32Z"/>
  `,
  "passport-folder": `
    <path fill="${C.gold}" d="M54 152h160l38 42h206v244H54V152Z"/>
    <path fill="${C.cream}" d="M118 74h224v300H118V74Z"/>
    <circle cx="230" cy="214" r="58" stroke="${C.orange}"/>
    <path d="M172 214h116M230 156c19 19 29 38 29 58s-10 39-29 58c-19-19-29-38-29-58s10-39 29-58Z" stroke="${C.orange}"/>
    <path d="M158 314h144"/>
    <path fill="${C.orange}" d="M54 236h404v202H54z"/>
  `,
  "secure-shield": `
    <path fill="${C.cream}" d="M256 48c70 50 126 58 170 62v126c0 106-64 178-170 228C150 414 86 342 86 236V110c44-4 100-12 170-62Z"/>
    <path fill="${C.gold}" d="M256 92c50 34 90 42 126 48v92c0 78-42 132-126 176-84-44-126-98-126-176v-92c36-6 76-14 126-48Z"/>
    <path d="m188 248 48 48 98-108" stroke="${C.white}" stroke-width="22"/>
  `,
};

async function renderSpots() {
  for (const [name, body] of Object.entries(icons)) {
    const source = svg(body);
    const svgPath = path.join(spotSvgDir, `${name}.svg`);
    const pngPath = path.join(spotPngDir, `${name}.png`);
    fs.writeFileSync(svgPath, source, "utf8");
    await sharp(Buffer.from(source)).resize(512, 512).png().toFile(pngPath);
  }
}

async function removeGreenAndResize(inputPath, outputPath) {
  const image = sharp(inputPath).ensureAlpha();
  const { data, info } = await image.raw().toBuffer({ resolveWithObject: true });

  for (let i = 0; i < data.length; i += 4) {
    const r = data[i];
    const g = data[i + 1];
    const b = data[i + 2];
    const a = data[i + 3];

    if (a < 8) {
      data[i] = 0;
      data[i + 1] = 0;
      data[i + 2] = 0;
      data[i + 3] = 0;
      continue;
    }

    const maxRB = Math.max(r, b);
    const greenScreen = g > 90 && g > maxRB + 8;
    if (greenScreen) {
      if (isV2) {
        data[i] = 157;
        data[i + 1] = 185;
        data[i + 2] = 164;
      } else {
        data[i] = 0;
        data[i + 1] = 0;
        data[i + 2] = 0;
        data[i + 3] = 0;
      }
      continue;
    }

    if (isV2) {
      const looksGold = r > 215 && g > 145 && b < 145 && g >= 0.62 * r;
      const looksSaffron = r > 185 && g > 70 && g < 185 && b < 105 && r > g * 1.2;
      if (looksGold) {
        data[i] = 246;
        data[i + 1] = 196;
        data[i + 2] = 69;
      } else if (looksSaffron) {
        data[i] = 242;
        data[i + 1] = 130;
        data[i + 2] = 12;
      }
    }
  }

  await sharp(data, {
    raw: { width: info.width, height: info.height, channels: 4 },
  })
    .resize(1600, 700, { fit: "fill", kernel: sharp.kernel.lanczos3 })
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toFile(outputPath);
}

async function renderHeroes() {
  const names = [
    "homepage",
    "flights",
    "hotels",
    "holidays",
    "umrah",
    "cruise",
    "visa",
    "business-travel",
    "about",
    "contact",
    "account",
  ];
  for (const name of names) {
    await removeGreenAndResize(
      path.join(heroSourceDir, `${name}.png`),
      path.join(heroOutputDir, `${name}.png`)
    );
  }
}

Promise.all([renderSpots(), renderHeroes()])
  .then(() => {
    console.log(
      `Built ${Object.keys(icons).length} SVG/PNG spots and 11 transparent hero PNGs${isV2 ? " in illustrations-v2" : ""}.`
    );
  })
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
