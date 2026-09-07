# Weiss Tea Time PDF Card Extractor

Extracts card images and translations from a Tea Time PDF and saves each card as an image with its translation overlaid.

## Requirements

- Python 3.9+

Install the dependencies:

```bash
pip install pdfplumber pymupdf pillow
```

## Usage

```bash
python main.py path/to/your/file.pdf
```

Output images are saved to an `output/` folder (created automatically), one file per card, named after the card's ID.