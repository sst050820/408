import { createWriteStream } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { getDocument } from "pdfjs-dist/legacy/build/pdf.mjs";

function usage() {
  console.error(
    [
      "Usage:",
      "  node extract.mjs inventory <input.pdf> <output.json>",
      "  node extract.mjs text <input.pdf> <output.ndjson> [startPage] [endPage]",
    ].join("\n"),
  );
  process.exit(2);
}

function normalizeText(text) {
  return text
    .replace(/\u0000/g, "")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function textItemsToLines(items) {
  const lines = [];
  let current = "";
  let lastY = null;

  for (const item of items) {
    if (!item || typeof item.str !== "string") {
      continue;
    }
    const y = Array.isArray(item.transform) ? item.transform[5] : null;
    const movedToNewLine =
      lastY !== null && y !== null && Math.abs(y - lastY) > 2.5;

    if (movedToNewLine && current.trim()) {
      lines.push(current.trimEnd());
      current = "";
    }

    const value = item.str;
    if (value) {
      if (
        current &&
        !/\s$/.test(current) &&
        !/^\s/.test(value) &&
        /[A-Za-z0-9)]$/.test(current) &&
        /^[A-Za-z0-9(]/.test(value)
      ) {
        current += " ";
      }
      current += value;
    }

    if (item.hasEOL) {
      if (current.trim()) {
        lines.push(current.trimEnd());
      }
      current = "";
    }
    lastY = y;
  }

  if (current.trim()) {
    lines.push(current.trimEnd());
  }
  return normalizeText(lines.join("\n"));
}

async function openPdf(pdfPath) {
  const bytes = new Uint8Array(await readFile(pdfPath));
  const loadingTask = getDocument({
    data: bytes,
    useSystemFonts: true,
    isEvalSupported: false,
    disableFontFace: true,
    verbosity: 0,
  });
  return loadingTask.promise;
}

async function resolveDestinationPage(pdf, destination) {
  if (!destination) {
    return null;
  }
  let explicit = destination;
  if (typeof destination === "string") {
    explicit = await pdf.getDestination(destination);
  }
  if (!Array.isArray(explicit) || explicit.length === 0) {
    return null;
  }

  const reference = explicit[0];
  if (Number.isInteger(reference)) {
    return reference + 1;
  }
  try {
    return (await pdf.getPageIndex(reference)) + 1;
  } catch {
    return null;
  }
}

async function resolveOutline(pdf, items, depth = 0) {
  if (!Array.isArray(items)) {
    return [];
  }
  const result = [];
  for (const item of items) {
    result.push({
      title: String(item.title ?? "").trim(),
      depth,
      page: await resolveDestinationPage(pdf, item.dest),
      bold: Boolean(item.bold),
      italic: Boolean(item.italic),
      items: await resolveOutline(pdf, item.items, depth + 1),
    });
  }
  return result;
}

function flattenOutline(items, output = []) {
  for (const item of items) {
    output.push({
      title: item.title,
      depth: item.depth,
      page: item.page,
    });
    flattenOutline(item.items, output);
  }
  return output;
}

async function extractPage(pdf, pageNumber, pageLabels) {
  const page = await pdf.getPage(pageNumber);
  const content = await page.getTextContent({
    includeMarkedContent: false,
    disableNormalization: false,
  });
  const text = textItemsToLines(content.items);
  const viewport = page.getViewport({ scale: 1 });
  page.cleanup();
  return {
    page: pageNumber,
    label: pageLabels?.[pageNumber - 1] ?? null,
    width: Math.round(viewport.width * 100) / 100,
    height: Math.round(viewport.height * 100) / 100,
    rotation: viewport.rotation,
    item_count: content.items.length,
    char_count: text.length,
    text,
  };
}

function collectSamplePages(numPages, flatOutline) {
  const pages = new Set();
  for (let page = 1; page <= Math.min(12, numPages); page += 1) {
    pages.add(page);
  }
  pages.add(numPages);

  const interval = Math.max(1, Math.floor(numPages / 10));
  for (let page = 1; page <= numPages; page += interval) {
    pages.add(page);
  }

  for (const item of flatOutline) {
    if (Number.isInteger(item.page)) {
      pages.add(item.page);
    }
    if (pages.size >= 50) {
      break;
    }
  }
  return [...pages]
    .filter((page) => page >= 1 && page <= numPages)
    .sort((a, b) => a - b);
}

async function inventory(pdfPath, outputPath) {
  const started = Date.now();
  const pdf = await openPdf(pdfPath);
  try {
    const metadataResult = await pdf.getMetadata();
    const pageLabels = await pdf.getPageLabels();
    const rawOutline = await pdf.getOutline();
    const outline = await resolveOutline(pdf, rawOutline);
    const flatOutline = flattenOutline(outline);
    const samplePageNumbers = collectSamplePages(pdf.numPages, flatOutline);
    const samples = [];

    for (const pageNumber of samplePageNumbers) {
      const page = await extractPage(pdf, pageNumber, pageLabels);
      samples.push({
        ...page,
        text: page.text.slice(0, 1600),
      });
      console.error(
        `inventory ${path.basename(pdfPath)}: sampled page ${pageNumber}/${pdf.numPages}`,
      );
    }

    const metadata =
      typeof metadataResult.metadata?.getAll === "function"
        ? metadataResult.metadata.getAll()
        : null;
    const report = {
      source: path.resolve(pdfPath),
      file_name: path.basename(pdfPath),
      num_pages: pdf.numPages,
      fingerprints: pdf.fingerprints,
      info: metadataResult.info ?? null,
      metadata,
      content_disposition_filename:
        metadataResult.contentDispositionFilename ?? null,
      content_length: metadataResult.contentLength ?? null,
      page_labels: pageLabels,
      outline,
      outline_flat: flatOutline,
      sample_pages: samples,
      extraction: {
        tool: "pdfjs-dist",
        version: "6.1.200",
        elapsed_ms: Date.now() - started,
      },
    };
    await mkdir(path.dirname(outputPath), { recursive: true });
    await writeFile(outputPath, JSON.stringify(report, null, 2), "utf8");
    console.log(
      JSON.stringify({
        file: report.file_name,
        pages: report.num_pages,
        outline_items: flatOutline.length,
        sampled_pages: samples.length,
        output: path.resolve(outputPath),
      }),
    );
  } finally {
    await pdf.cleanup();
  }
}

async function extractText(pdfPath, outputPath, startArg, endArg) {
  const pdf = await openPdf(pdfPath);
  const pageLabels = await pdf.getPageLabels();
  const startPage = Math.max(1, Number.parseInt(startArg ?? "1", 10));
  const endPage = Math.min(
    pdf.numPages,
    Number.parseInt(endArg ?? String(pdf.numPages), 10),
  );
  if (!Number.isInteger(startPage) || !Number.isInteger(endPage)) {
    throw new Error("startPage and endPage must be integers");
  }
  if (startPage > endPage) {
    throw new Error(`Invalid page range: ${startPage}-${endPage}`);
  }

  await mkdir(path.dirname(outputPath), { recursive: true });
  const output = createWriteStream(outputPath, { encoding: "utf8" });
  let totalChars = 0;
  let emptyPages = 0;
  const started = Date.now();

  try {
    for (let pageNumber = startPage; pageNumber <= endPage; pageNumber += 1) {
      const page = await extractPage(pdf, pageNumber, pageLabels);
      totalChars += page.char_count;
      if (page.char_count === 0) {
        emptyPages += 1;
      }
      if (!output.write(`${JSON.stringify(page)}\n`)) {
        await new Promise((resolve) => output.once("drain", resolve));
      }
      if (
        pageNumber === startPage ||
        pageNumber === endPage ||
        pageNumber % 25 === 0
      ) {
        console.error(
          `text ${path.basename(pdfPath)}: page ${pageNumber}/${endPage}`,
        );
      }
    }
  } finally {
    await new Promise((resolve, reject) => {
      output.end(resolve);
      output.on("error", reject);
    });
    await pdf.cleanup();
  }

  console.log(
    JSON.stringify({
      file: path.basename(pdfPath),
      start_page: startPage,
      end_page: endPage,
      pages: endPage - startPage + 1,
      total_chars: totalChars,
      empty_pages: emptyPages,
      elapsed_ms: Date.now() - started,
      output: path.resolve(outputPath),
    }),
  );
}

const [mode, pdfPath, outputPath, startPage, endPage] = process.argv.slice(2);
if (!mode || !pdfPath || !outputPath) {
  usage();
}

if (mode === "inventory") {
  await inventory(pdfPath, outputPath);
} else if (mode === "text") {
  await extractText(pdfPath, outputPath, startPage, endPage);
} else {
  usage();
}
