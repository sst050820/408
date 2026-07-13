#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Batch OCR a PDF through the SiliconFlow OpenAI-compatible API."""

import base64
import os
import re
import sys
import time
from pathlib import Path

import pypdfium2 as pdfium
from openai import OpenAI


API_BASE = "https://api.siliconflow.cn/v1"
MODEL = "PaddlePaddle/PaddleOCR-VL-1.5"
SCALE = 2.0


def get_api_key():
    """Read the SiliconFlow API key without storing it in source code."""
    api_key = os.environ.get("SILICONFLOW_API_KEY")
    if not api_key:
        raise RuntimeError(
            "Missing SILICONFLOW_API_KEY. Configure the environment variable before running OCR."
        )
    return api_key


def image_to_data_url(image_path):
    """Encode a local image as a PNG data URL."""
    with open(image_path, "rb") as image_file:
        encoded = base64.b64encode(image_file.read()).decode("utf-8")
    return f"data:image/png;base64,{encoded}"


def ocr_page(image_path):
    """Recognize one rendered page and return Markdown text."""
    client = OpenAI(api_key=get_api_key(), base_url=API_BASE)
    response = client.chat.completions.create(
        model=MODEL,
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": (
                            "请对这页教材进行 OCR。完整保留标题、正文、公式、表格、代码、"
                            "图注和页码，并用结构清晰的 Markdown 输出；不要总结或省略。"
                        ),
                    },
                    {
                        "type": "image_url",
                        "image_url": {"url": image_to_data_url(image_path)},
                    },
                ],
            }
        ],
        temperature=0,
    )
    return response.choices[0].message.content or ""


def safe_stem(name):
    """Return a filename-safe stem while preserving Chinese characters."""
    return re.sub(r'[<>:"/\\|?*]+', "_", name).strip(" .")


def process_pdf(pdf_path, output_dir, start_page=0):
    """Render and OCR a PDF from a zero-based start page."""
    pdf_path = Path(pdf_path).resolve()
    output_dir = Path(output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    document = pdfium.PdfDocument(str(pdf_path))
    page_total = len(document)
    if start_page < 0 or start_page >= page_total:
        raise ValueError(f"start_page 必须位于 0 到 {page_total - 1} 之间")

    book_dir = output_dir / safe_stem(pdf_path.stem)
    book_dir.mkdir(parents=True, exist_ok=True)
    merged_path = output_dir / f"{safe_stem(pdf_path.stem)}_全文.md"

    for page_index in range(start_page, page_total):
        page_number = page_index + 1
        page_output = book_dir / f"page_{page_number:04d}.md"
        if page_output.exists() and page_output.stat().st_size > 0:
            print(f"[{page_number}/{page_total}] 已存在，跳过：{page_output.name}")
            continue

        temporary_image = book_dir / f".page_{page_number:04d}.png"
        try:
            page = document[page_index]
            bitmap = page.render(scale=SCALE)
            bitmap.to_pil().save(temporary_image)
            text = ocr_page(temporary_image)
            page_output.write_text(text.strip() + "\n", encoding="utf-8")
            print(f"[{page_number}/{page_total}] 完成：{page_output.name}")
        except Exception as error:
            print(f"[{page_number}/{page_total}] 失败：{error}", file=sys.stderr)
            print("稍后可使用同一页码重新运行。", file=sys.stderr)
            raise
        finally:
            if temporary_image.exists():
                temporary_image.unlink()

        time.sleep(1)

    with merged_path.open("w", encoding="utf-8") as merged_file:
        for page_index in range(page_total):
            page_number = page_index + 1
            page_output = book_dir / f"page_{page_number:04d}.md"
            if not page_output.exists():
                continue
            merged_file.write(f"\n\n<!-- page: {page_number} -->\n\n")
            merged_file.write(page_output.read_text(encoding="utf-8"))

    print(f"合并完成：{merged_path}")


def main():
    if len(sys.argv) not in (2, 3):
        print("用法：python batch_ocr.py <PDF路径> [0-based起始页]", file=sys.stderr)
        return 2

    pdf_path = Path(sys.argv[1])
    start_page = int(sys.argv[2]) if len(sys.argv) == 3 else 0
    output_dir = Path(__file__).resolve().parent / "output"
    process_pdf(pdf_path, output_dir, start_page)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
