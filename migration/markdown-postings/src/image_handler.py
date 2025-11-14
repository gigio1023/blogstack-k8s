"""
Image file handler for Hugo to Ghost migration

This module handles finding, copying, and path conversion of image files
from Hugo's structure to Ghost's content/images directory.
"""

import shutil
from pathlib import Path
from typing import Any


class ImageHandler:
    """
    Handler for image file operations
    
    Manages image file discovery in Hugo's directory structure,
    copies them to Ghost's expected location, and maintains a
    mapping of old to new paths for content replacement.
    
    Hugo typically stores images in:
    - static/
    - content/
    - assets/
    
    Ghost expects images in:
    - content/images/
    """

    def __init__(self, hugo_root: Path, output_dir: Path):
        """
        Initialize image handler
        
        Args:
            hugo_root: Root directory of Hugo project for image search
            output_dir: Output directory where images/ subdirectory will be created
        """
        self.hugo_root: Path = hugo_root
        self.output_dir: Path = output_dir
        self.images_dir: Path = output_dir / "images"
        self.images_dir.mkdir(parents=True, exist_ok=True)
        
        # Track image path mappings: Hugo path -> Ghost path
        self.path_mapping: dict[str, str] = {}

    def _find_image_file(self, image_path: str) -> Path | None:
        """
        Find image file in Hugo project directory structure
        
        Searches for the image in multiple common Hugo locations:
        - Project root
        - static/ directory
        - content/ directory (for page bundles)
        - assets/ directory
        
        Args:
            image_path: Relative image path from Hugo markdown
            
        Returns:
            Path to image file if found, None otherwise
        """
        # Remove leading slash for consistent path handling
        clean_path: str = image_path.lstrip("/")
        
        # Common Hugo image locations
        possible_locations: list[Path] = [
            self.hugo_root / clean_path,
            self.hugo_root / "static" / clean_path,
            self.hugo_root / "content" / clean_path,
            self.hugo_root / "assets" / clean_path,
        ]
        
        for location in possible_locations:
            if location.exists() and location.is_file():
                return location
        
        return None

    def copy_image(self, image_path: str) -> str | None:
        """
        Copy image file to Ghost directory and return new path
        
        Finds the image in Hugo's directory structure, copies it to
        the output images/ directory, and generates the Ghost path.
        Handles filename conflicts by appending a counter.
        
        Args:
            image_path: Original Hugo image path
            
        Returns:
            Ghost image path (/content/images/...), or None if image not found
        """
        # Return cached path if already processed
        if image_path in self.path_mapping:
            return self.path_mapping[image_path]
        
        source_file: Path | None = self._find_image_file(image_path)
        
        if not source_file:
            return None
        
        # Prepare destination path: images/filename.ext
        filename: str = source_file.name
        dest_file: Path = self.images_dir / filename
        
        # Handle filename conflicts by adding numeric suffix
        counter: int = 1
        while dest_file.exists():
            stem: str = source_file.stem
            suffix: str = source_file.suffix
            dest_file = self.images_dir / f"{stem}_{counter}{suffix}"
            counter += 1
        
        # Copy file with metadata preservation
        shutil.copy2(source_file, dest_file)
        
        # Generate Ghost path format: /content/images/filename.ext
        ghost_path: str = f"/content/images/{dest_file.name}"
        self.path_mapping[image_path] = ghost_path
        
        return ghost_path

    def process_post_images(self, post_data: dict[str, Any]) -> dict[str, str]:
        """
        Process all images referenced in a post
        
        Handles both the feature image (from frontmatter) and all
        images found in the post content. Returns a mapping for
        path replacement in the content.
        
        Args:
            post_data: Dictionary containing post metadata and content
            
        Returns:
            Dictionary mapping old Hugo paths to new Ghost paths
        """
        mapping: dict[str, str] = {}
        
        # Process feature/cover image from frontmatter
        if post_data.get("feature_image"):
            ghost_path: str | None = self.copy_image(post_data["feature_image"])
            if ghost_path:
                mapping[post_data["feature_image"]] = ghost_path
        
        # Process all images found in content
        for img_path in post_data.get("images", []):
            ghost_path = self.copy_image(img_path)
            if ghost_path:
                mapping[img_path] = ghost_path
        
        return mapping

