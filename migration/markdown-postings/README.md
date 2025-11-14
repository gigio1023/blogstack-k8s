# Hugo to Ghost Migration

Convert Hugo markdown posts to Ghost import JSON format.

## Installation

```bash
cd migration/markdown-postings
uv sync
```

## Usage

```bash
uv run main.py \
  --input-dir /path/to/hugo/content/posts \
  --hugo-root /path/to/hugo/project \
  --output-dir output
```

## Options

- `-i, --input-dir`: Hugo content directory (required)
- `-r, --hugo-root`: Hugo project root for image search (required)
- `-o, --output-dir`: Output directory (default: output)
- `--create-zip/--no-zip`: Create zip package (default: True)
- `-v, --verbose`: Enable verbose logging

## Output Structure

```
output/
├── migrate.json
└── images/
    └── *.jpg

output.zip
```

## Supported Frontmatter Fields

- `title`, `date`, `publishDate`, `slug`, `url`
- `tags`, `cover`, `image`, `thumbnail`, `featured_image`
- `description`, `summary`, `excerpt`, `draft`

## Image Handling

Automatically detects and copies images from:
- Frontmatter fields
- Markdown syntax: `![alt](path)`
- HTML tags: `<img src="path">`
- Hugo shortcodes: `{{< figure src="path" >}}`

Search paths:
- `{hugo-root}/{path}`
- `{hugo-root}/static/{path}`
- `{hugo-root}/content/{path}`
- `{hugo-root}/assets/{path}`

## Ghost Import

1. Access Ghost admin panel
2. Settings → Labs → Import content
3. Upload `output.zip`
4. Verify imported posts

## Example

Input (Hugo):

```markdown
---
title: "Sample Post"
date: 2023-05-01T10:20:30Z
slug: "sample-post"
tags: ["sample"]
cover: "/images/sample.jpg"
---

Content here.
```

Output (Ghost JSON):

```json
{
  "meta": {"exported_on": 1699876543000, "version": "5.0.0"},
  "data": {
    "posts": [{
      "title": "Sample Post",
      "slug": "sample-post",
      "feature_image": "/content/images/sample.jpg",
      "published_at": "2023-05-01T10:20:30",
      "mobiledoc": "{...}"
    }],
    "tags": [...],
    "posts_tags": [...]
  }
}
```

## Notes

- External URLs are not converted
- Duplicate image filenames are auto-numbered
- Verify posts in Ghost after import
- Requires Ghost 5.0+

