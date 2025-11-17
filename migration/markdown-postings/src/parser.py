"""
Hugo markdown frontmatter parser

This module provides functionality to parse Hugo markdown files,
extracting frontmatter metadata and content for Ghost migration.
Supports YAML, TOML, and JSON frontmatter formats.
"""

import re
from pathlib import Path
from datetime import datetime
from typing import Any
import frontmatter
from dateutil import parser as dateparser


class HugoPostParser:
    """
    Parser for Hugo markdown posts
    
    Parses Hugo markdown files with frontmatter and extracts metadata
    including title, date, tags, images, and content. Handles multiple
    frontmatter formats (YAML, TOML, JSON) through python-frontmatter.
    """

    def __init__(self, file_path: Path):
        """
        Initialize parser with a markdown file
        
        Args:
            file_path: Path to the Hugo markdown file
        """
        self.file_path: Path = file_path
        self.post: frontmatter.Post = frontmatter.load(file_path)
        self.metadata: dict[str, Any] = dict(self.post.metadata)
        self.content: str = self.post.content

    def get_title(self) -> str:
        """
        Extract post title from frontmatter
        
        Returns:
            Post title, or filename if not specified in frontmatter
        """
        return self.metadata.get("title", self.file_path.stem)

    def get_slug(self) -> str:
        """
        Extract or generate post slug
        
        Tries to get slug from frontmatter 'slug' field first,
        then from 'url' field, finally falls back to filename.
        Handles empty slugs from trailing slashes in URLs.
        
        Returns:
            Post slug for URL
        """
        slug: str | None = self.metadata.get("slug")
        if slug:
            return slug
        
        # Try to extract slug from url field
        url: str | None = self.metadata.get("url")
        if url:
            slug_from_url: str = url.strip("/").split("/")[-1]
            if slug_from_url:
                return slug_from_url
            # Fallback to filename if slug is empty (e.g., URL ends with /)
        
        # Fallback to filename
        return self.file_path.stem

    def get_published_at(self) -> str | None:
        """
        Extract and convert publication date to ISO8601 format
        
        Checks 'date' and 'publishDate' fields in frontmatter.
        Handles both datetime objects and string formats.
        
        Returns:
            ISO8601 formatted date string, or None if not found
        """
        date_value: Any = self.metadata.get("date") or self.metadata.get("publishDate")
        
        if not date_value:
            return None
        
        # Handle datetime objects directly
        if isinstance(date_value, datetime):
            return date_value.isoformat()
        
        # Parse date strings
        if isinstance(date_value, str):
            try:
                dt: datetime = dateparser.parse(date_value)
                return dt.isoformat() if dt else None
            except Exception:
                return None
        
        return None

    def get_tags(self) -> list[str]:
        """
        Extract tags from frontmatter
        
        Handles both comma-separated string and list formats.
        
        Returns:
            List of tag names
        """
        tags: Any = self.metadata.get("tags", [])
        
        # Handle comma-separated string
        if isinstance(tags, str):
            return [t.strip() for t in tags.split(",")]
        
        # Handle list format
        if isinstance(tags, list):
            return [str(t).strip() for t in tags]
        
        return []

    def get_feature_image(self) -> str | None:
        """
        Extract feature/cover image path from frontmatter
        
        Checks multiple common field names used in Hugo themes:
        cover, image, thumbnail, featured_image
        
        Returns:
            Image path, or None if not found
        """
        image: str | None = (
            self.metadata.get("cover") or
            self.metadata.get("image") or
            self.metadata.get("thumbnail") or
            self.metadata.get("featured_image")
        )
        
        return image if image else None

    def get_excerpt(self) -> str | None:
        """
        Extract post excerpt/summary from frontmatter
        
        Checks multiple common field names:
        description, summary, excerpt
        
        Returns:
            Excerpt text, or None if not found
        """
        excerpt: str | None = (
            self.metadata.get("description") or
            self.metadata.get("summary") or
            self.metadata.get("excerpt")
        )
        
        return excerpt if excerpt else None

    def get_status(self) -> str:
        """
        Determine post status (draft or published)
        
        Checks 'draft' field in frontmatter. Handles both
        boolean and string values.
        
        Returns:
            "draft" or "published"
        """
        draft: Any = self.metadata.get("draft", False)
        
        if isinstance(draft, bool):
            return "draft" if draft else "published"
        
        # Handle string values like "true", "yes", "1"
        if isinstance(draft, str):
            return "draft" if draft.lower() in ["true", "yes", "1"] else "published"
        
        return "published"

    def find_images_in_content(self) -> list[str]:
        """
        Find all image references in post content
        
        Detects images in multiple formats:
        - Markdown syntax: ![alt](path)
        - HTML img tags: <img src="path">
        - Hugo figure shortcode: {{< figure src="path" >}} or {{% figure src="path" %}}
        
        Note: Hugo figure shortcodes are detected here for image copying,
        but are NOT automatically converted to Ghost-compatible format.
        Manual conversion may be needed if Jekyll/Hugo-specific shortcodes exist.
        
        Filters out external URLs (http/https).
        
        Returns:
            List of local image paths found in content
        """
        images: list[str] = []
        
        # Markdown images: ![alt](path)
        md_images: list[str] = re.findall(r"!\[.*?\]\((.*?)\)", self.content)
        images.extend(md_images)
        
        # HTML img tags: <img src="path">
        html_images: list[str] = re.findall(r'<img[^>]+src=["\'](.*?)["\']', self.content)
        images.extend(html_images)
        
        # Hugo figure shortcode: {{< figure src="path" >}} or {{% figure src="path" %}}
        # Support both < and % delimiters for shortcode syntax
        figure_images: list[str] = re.findall(r'\{\{[<%]\s*figure\s+src=["\'](.*?)["\']\s*.*?[>%]\}\}', self.content)
        images.extend(figure_images)
        
        # Filter out external URLs
        return [img for img in images if not img.startswith(("http://", "https://"))]

    def to_dict(self) -> dict[str, Any]:
        """
        Convert parsed post data to dictionary
        
        Aggregates all extracted metadata and content into a
        single dictionary structure for easy processing.
        
        Returns:
            Dictionary containing all post data
        """
        return {
            "title": self.get_title(),
            "slug": self.get_slug(),
            "published_at": self.get_published_at(),
            "tags": self.get_tags(),
            "feature_image": self.get_feature_image(),
            "excerpt": self.get_excerpt(),
            "status": self.get_status(),
            "content": self.content,
            "images": self.find_images_in_content(),
            "source_file": str(self.file_path),
        }

