"""
Ghost import JSON exporter

This module generates Ghost import JSON files according to Ghost's
import format specification. The JSON includes posts, tags, and their
relationships in a structure that Ghost can import directly.
"""

import json
from datetime import datetime
from pathlib import Path
from typing import Any

from .converter import MobiledocConverter


class GhostExporter:
    """
    Ghost import JSON generator
    
    Aggregates converted posts, tags, and relationships into a single
    JSON file that conforms to Ghost's import format. The format includes:
    - meta: export metadata (timestamp, version)
    - data: posts, tags, posts_tags relationships
    
    Ghost import format reference:
    https://ghost.org/docs/migration/custom/
    """

    def __init__(self):
        """
        Initialize exporter with empty collections
        """
        self.posts: list[dict[str, Any]] = []
        self.tags: dict[str, dict[str, Any]] = {}  # Deduplicated: tag_name -> tag_object
        self.posts_tags: list[dict[str, Any]] = []  # Post-tag relationships

    def add_post(
        self,
        post_data: dict[str, Any],
        content: str,
        image_mapping: dict[str, str]
    ) -> None:
        """
        Add a post to the export collection
        
        Processes post content, converts image paths, generates Mobiledoc,
        and creates tag relationships. Each post gets a unique ID.
        
        Args:
            post_data: Post metadata from parser
            content: Raw markdown content
            image_mapping: Hugo to Ghost image path mappings
        """
        # Convert image paths in content
        converted_content: str = MobiledocConverter.convert_image_paths(
            content,
            image_mapping
        )
        
        # Generate Mobiledoc JSON
        mobiledoc: str = MobiledocConverter.create_mobiledoc(converted_content)
        
        # Convert feature image path if present
        feature_image: str | None = None
        if post_data.get("feature_image"):
            feature_image = image_mapping.get(
                post_data["feature_image"],
                post_data["feature_image"]  # Fallback to original if not mapped
            )
        
        # Create Ghost post object
        post_id: str = f"post-{len(self.posts) + 1}"
        ghost_post: dict[str, Any] = {
            "id": post_id,
            "title": post_data["title"],
            "slug": post_data["slug"],
            "mobiledoc": mobiledoc,
            "status": post_data.get("status", "published"),
            "created_at": post_data.get("published_at") or datetime.now().isoformat(),
            "published_at": post_data.get("published_at"),
            "updated_at": post_data.get("published_at") or datetime.now().isoformat(),
        }
        
        # Add optional fields
        if feature_image:
            ghost_post["feature_image"] = feature_image
        
        if post_data.get("excerpt"):
            ghost_post["custom_excerpt"] = post_data["excerpt"]
        
        self.posts.append(ghost_post)
        
        # Process tags and create relationships
        for tag_name in post_data.get("tags", []):
            self._add_tag(tag_name)
            self._link_post_tag(post_id, tag_name)

    def _add_tag(self, tag_name: str) -> None:
        """
        Add a tag to the collection (deduplicates automatically)
        
        Args:
            tag_name: Name of the tag
        """
        if tag_name not in self.tags:
            tag_id: str = f"tag-{len(self.tags) + 1}"
            self.tags[tag_name] = {
                "id": tag_id,
                "name": tag_name,
                "slug": tag_name.lower().replace(" ", "-"),
            }

    def _link_post_tag(self, post_id: str, tag_name: str) -> None:
        """
        Create post-tag relationship
        
        Args:
            post_id: ID of the post
            tag_name: Name of the tag
        """
        tag_obj: dict[str, Any] = self.tags[tag_name]
        self.posts_tags.append({
            "post_id": post_id,
            "tag_id": tag_obj["id"],
        })

    def generate_json(self) -> dict[str, Any]:
        """
        Generate complete Ghost import JSON structure
        
        Returns:
            Dictionary containing Ghost import format with meta and data
        """
        return {
            "meta": {
                "exported_on": int(datetime.now().timestamp() * 1000),  # Unix timestamp in ms
                "version": "5.0.0"  # Ghost version format
            },
            "data": {
                "posts": self.posts,
                "tags": list(self.tags.values()),
                "posts_tags": self.posts_tags,
            }
        }

    def export_to_file(self, output_path: Path) -> None:
        """
        Write Ghost import JSON to file
        
        Args:
            output_path: Path where JSON file will be written
        """
        data: dict[str, Any] = self.generate_json()
        
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)

