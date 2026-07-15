import { readFile, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { createCanvas } from "@napi-rs/canvas";
import { getDocument } from "pdfjs-dist/legacy/build/pdf.mjs";

function usage() {
  console.error(
    "Usage: node render.mjs <input.pdf> <output-dir> <pages> [scale]\n" +
      "Example: node render.mjs book.pdf rendered 13,14,20-22 2.5",
  );
  process.exit(2);
}

function parsePages(specification, maxPage) {
  const pages = new Set();
  for (const part of specification.split(",")) {
    const token = part.trim();
    if (!token) {
      continue;
    }
    if (token.includes("-")) {
      const [startText, endText] = token.split("-", 2);
      const start = Number.parseInt(startText, 10);
      const end = Number.parseInt(endText, 10);
      if (!Number.isInteger(start) || !Number.isInteger(end) || start > end) {
        throw new Error(`Invalid page range: ${token}`);
      }
      for (let page = start; page <= end; page += 1) {
        pages.add(page);
      }
    } else {
      const page = Number.parseInt(token, 10);
      if (!Number.isInteger(page)) {
        throw new Error(`Invalid page number: ${token}`);
      }
      pages.add(page);
    }
  }
  const sorted = [...pages].sort((a, b) => a - b);
  for (const page of sorted) {
    if (page < 1 || page > maxPage) {
      throw new Error(`Page ${page} is outside 1-${maxPage}`);
    }
  }
  return sorted;
}

const [pdfPath, outputDir, pageSpecification, scaleText] =
  process.argv.slice(2);
if (!pdfPath || !outputDir || !pageSpecification) {
  usage();
}

const scale = Number.parseFloat(scaleText ?? "2.5");
if (!Number.isFinite(scale) || scale <= 0 || scale > 5) {
  throw new Error("Scale must be greater than 0 and no more than 5");
}

const data = new Uint8Array(await readFile(pdfPath));
const pdf = await getDocument({
  data,
  useSystemFonts: true,
  isEvalSupported: false,
  verbosity: 0,
}).promise;

try {
  const pages = parsePages(pageSpecification, pdf.numPages);
  await mkdir(outputDir, { recursive: true });
  const outputs = [];

  for (const pageNumber of pages) {
    const page = await pdf.getPage(pageNumber);
    const viewport = page.getViewport({ scale });
    const canvas = createCanvas(
      Math.ceil(viewport.width),
      Math.ceil(viewport.height),
    );
    const context = canvas.getContext("2d");
    context.fillStyle = "#ffffff";
    context.fillRect(0, 0, canvas.width, canvas.height);
    await page.render({
      canvasContext: context,
      viewport,
      canvas,
      background: "#ffffff",
    }).promise;

    const fileName = `page-${String(pageNumber).padStart(4, "0")}.png`;
    const outputPath = path.join(outputDir, fileName);
    await writeFile(outputPath, canvas.toBuffer("image/png"));
    outputs.push({
      page: pageNumber,
      output: path.resolve(outputPath),
      width: canvas.width,
      height: canvas.height,
    });
    page.cleanup();
    console.error(
      `render ${path.basename(pdfPath)}: page ${pageNumber}/${pdf.numPages}`,
    );
  }

  console.log(
    JSON.stringify({
      file: path.basename(pdfPath),
      total_pages: pdf.numPages,
      scale,
      rendered: outputs,
    }),
  );
} finally {
  await pdf.cleanup();
}
