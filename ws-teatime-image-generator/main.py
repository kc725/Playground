import os, io
import re
import argparse
from pathlib import Path

import pdfplumber
import pymupdf as fitz
from PIL import Image, ImageDraw, ImageFont
import textwrap

#teatime PDF column definitions
# 0 - 100: ID
# 100 - 170: card image
# 170 - 400: card translation
COLUMN_DEFINITIONS = {0, 100, 170, 400}

# Named ranges derived from the boundaries above, so each column crop
# reads clearly at the call site.
_bounds = sorted(COLUMN_DEFINITIONS)
ID_COLUMN = (_bounds[0], _bounds[1])            # 0 - 100
IMAGE_COLUMN = (_bounds[1], _bounds[2])         # 100 - 170
TRANSLATION_COLUMN = (_bounds[2], _bounds[3])   # 170 - 400

# Characters that aren't safe in filenames on common filesystems
# (this covers the "/" from raw IDs like "12/34", plus the usual
# Windows-reserved set for good measure).
_UNSAFE_FILENAME_CHARS = re.compile(r'[\\/:*?"<>|]')

def sanitize_filename(name: str, replacement: str = "-") -> str:
    """Replace filesystem-unsafe characters so a raw ID can be used as a filename."""
    cleaned = _UNSAFE_FILENAME_CHARS.sub(replacement, name).strip()
    return cleaned or "untitled"

TEXT_X0 = 25
TEXT_X1 = 440
TEXT_Y0 = 400
TEXT_Y1 = 570

def overlay_translation(
    image_bytes: bytes,
    translation: str,
    font_path: str = None,
) -> Image.Image:
    """Return a copy of the card image with a solid white band containing
    the translation text, confined to a vertical region at the bottom."""
    base = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    draw = ImageDraw.Draw(base)

    # Solid white background for the band
    draw.rectangle([(TEXT_X0, TEXT_Y0), (TEXT_X1, TEXT_Y1)], fill=(255, 255, 255))

    font_size = 18
    font = ImageFont.truetype(font_path, font_size) if font_path else ImageFont.load_default()

    wrapped = textwrap.fill(translation, width=415//5)

    text_bbox = draw.multiline_textbbox((0, 0), wrapped, font=font)
    text_w = text_bbox[2] - text_bbox[0]
    text_h = text_bbox[3] - text_bbox[1]

    text_x = TEXT_X0 + 10
    text_y = TEXT_Y0 + (TEXT_Y1 - TEXT_Y0 - text_h) // 2
    draw.multiline_text((text_x, text_y), wrapped, font=font, fill=(0, 0, 0), align="left")

    return base

def main():
    # Set up the argument parser
    parser = argparse.ArgumentParser(description="Process a data file.")
    
    # Define a required argument for the file path
    parser.add_argument("filepath", type=Path, help="Path to the input file")

    args = parser.parse_args()

    # Verify the file exists before processing
    if not args.filepath.is_file():
        print(f"Error: The file '{args.filepath}' does not exist.")
        return

    # Read and process the file content
    raw_cards = []
    raw_ids = []
    raw_translations = []

    # pdfplumber is great for text/column layout, but page.to_image() only
    # gives you a rasterized re-render at a chosen DPI -- it resamples the
    # embedded image, which is why bumping resolution still looked blurry.
    # To get the original embedded image bytes at full native quality, pull
    # them out with PyMuPDF instead, using pdfplumber (or fitz) just to know
    # which images fall inside the card-image column.
    doc = fitz.open(args.filepath)

    with pdfplumber.open(args.filepath) as pdf:
        for page_number, page in enumerate(pdf.pages):
            fitz_page = doc[page_number]

            #Start by extracting the card images from the second column
            card_images = page.crop((IMAGE_COLUMN[0], 0, IMAGE_COLUMN[1], page.height))

            for i, card_image in enumerate(card_images.images):
                # Match this pdfplumber image's bounding box against
                # PyMuPDF's image position list for the page so we can
                # find its xref and pull the original embedded bytes.
                bbox = fitz.Rect(
                    card_image["x0"],
                    card_image["top"],
                    card_image["x1"],
                    card_image["bottom"],
                )

                for img in fitz_page.get_images(full=True):
                    xref = img[0]
                    for rect in fitz_page.get_image_rects(xref):
                        if rect.intersects(bbox):
                            base_image = doc.extract_image(xref)
                            image_bytes = base_image["image"]
                            image_ext = base_image["ext"]
                            raw_cards.append((image_bytes, image_ext))
                            break
                    else:
                        continue
                    break

                #Then extract the ID and translation text for this same
                #row, using the card image's vertical span (top/bottom) so
                #the text stays aligned with the row it belongs to.
                row_top = card_image["top"]
                if i+1 < len(card_images.images):
                    row_bottom = card_images.images[i+1]["top"]
                else:
                    row_bottom = page.height

                id_crop = page.crop((ID_COLUMN[0], row_top, ID_COLUMN[1], row_bottom))
                id_text = (id_crop.extract_text() or "").strip()
                raw_ids.append(id_text)

                translation_crop = page.crop(
                    (TRANSLATION_COLUMN[0], row_top, TRANSLATION_COLUMN[1], row_bottom)
                )
                translation_text = (translation_crop.extract_text() or "").strip()
                raw_translations.append(translation_text)
    doc.close()

    #Output the extracted card images and translations
    output_dir = "output"
    os.makedirs(output_dir, exist_ok=True)
    for index, ((image_bytes, image_ext), translation_text) in enumerate(zip(raw_cards, raw_translations)):
        if not translation_text:
            continue  # Skip saving if there's no translation text

        composited_image = overlay_translation(image_bytes, translation_text)
        # Use the card's own ID as the filename (sanitized, since raw IDs
        # can contain characters like "/" that aren't valid in filenames).
        # Falls back to card_{index} if there's no ID for this row.
        card_id = raw_ids[index] if index < len(raw_ids) and raw_ids[index] else f"card_{index}"
        safe_name = sanitize_filename(card_id)
        filename = os.path.join(output_dir, f"{safe_name}.{image_ext}")
        composited_image.save(filename)

    print(f"Saved {len(raw_cards)} card images with translations to '{output_dir}'\n")

    #debugging
    with open('output/output.txt', 'w') as file:
        for translation in raw_translations:
            file.write(f"{translation}\n")

if __name__ == "__main__":
    main()