#!/usr/bin/env python3
"""
Hugo to Ghost migration CLI

This is the main entry point for the Hugo to Ghost migration tool.
It orchestrates the entire conversion process:

1. Parse Hugo markdown files (frontmatter + content)
2. Extract and process images
3. Convert to Ghost Mobiledoc format
4. Generate Ghost import JSON
5. Package into zip file for Ghost import

Architecture:
- HugoPostParser: Parses Hugo markdown files with frontmatter
- ImageHandler: Finds, copies, and maps image paths
- MobiledocConverter: Converts markdown to Ghost's Mobiledoc format
- GhostExporter: Generates Ghost import JSON with posts, tags, relationships
- GhostPackager: Creates zip archive for Ghost import

Workflow:
1. Scan input directory for .md files
2. For each markdown file:
   a. Parse frontmatter and content
   b. Find and copy referenced images
   c. Convert image paths to Ghost format
   d. Generate Mobiledoc structure
   e. Add to export collection with tags
3. Write migrate.json with all posts and metadata
4. Create zip package with JSON and images
5. Ready for Ghost import via Admin UI

Usage:
    uv run main.py -i content/posts -r . -o output

Output:
    output/
    ├── migrate.json  (Ghost import JSON)
    └── images/       (copied image files)
    output.zip        (packaged for Ghost)
"""

import sys
from pathlib import Path
from typing import Any

import click
from loguru import logger

from src.parser import HugoPostParser
from src.image_handler import ImageHandler
from src.exporter import GhostExporter
from src.packager import GhostPackager


@click.command()
@click.option(
    "--input-dir",
    "-i",
    type=click.Path(exists=True, file_okay=False, path_type=Path),
    required=True,
    help="Hugo content directory path",
)
@click.option(
    "--hugo-root",
    "-r",
    type=click.Path(exists=True, file_okay=False, path_type=Path),
    required=True,
    help="Hugo project root directory",
)
@click.option(
    "--output-dir",
    "-o",
    type=click.Path(path_type=Path),
    default="output",
    help="Output directory (default: output)",
)
@click.option(
    "--create-zip/--no-zip",
    default=True,
    help="Create zip file (default: True)",
)
@click.option(
    "--verbose",
    "-v",
    is_flag=True,
    help="Enable verbose logging",
)
def cli(
    input_dir: Path,
    hugo_root: Path,
    output_dir: Path,
    create_zip: bool,
    verbose: bool,
) -> None:
    """
    Convert Hugo markdown posts to Ghost import JSON
    
    Main CLI function that orchestrates the entire migration process.
    Handles command-line arguments, initializes components, processes
    all markdown files, and generates the final Ghost import package.
    
    Args:
        input_dir: Directory containing Hugo markdown files
        hugo_root: Hugo project root for finding images
        output_dir: Where to write migrate.json and images
        create_zip: Whether to create zip package
        verbose: Enable debug logging
    """
    
    # Configure logging based on verbosity level
    logger.remove()
    if verbose:
        logger.add(sys.stderr, level="DEBUG")
    else:
        logger.add(sys.stderr, level="INFO", format="<level>{message}</level>")
    
    # Log configuration
    logger.info(f"Input: {input_dir}")
    logger.info(f"Hugo root: {hugo_root}")
    logger.info(f"Output: {output_dir}")
    
    # Ensure output directory exists
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Initialize components
    # ImageHandler: manages image file discovery and copying
    image_handler: ImageHandler = ImageHandler(hugo_root, output_dir)
    # GhostExporter: aggregates posts, tags, and relationships into Ghost JSON
    exporter: GhostExporter = GhostExporter()
    
    # Discover all markdown files recursively
    md_files: list[Path] = list(input_dir.rglob("*.md"))
    
    if not md_files:
        logger.error("No markdown files found")
        sys.exit(1)
    
    logger.info(f"Found {len(md_files)} posts")
    
    # Process each markdown file
    success_count: int = 0
    error_count: int = 0
    
    for md_file in md_files:
        try:
            # Step 1: Parse Hugo markdown file
            parser: HugoPostParser = HugoPostParser(md_file)
            post_data: dict[str, Any] = parser.to_dict()
            
            # Step 2: Process images (find, copy, generate path mappings)
            image_mapping: dict[str, str] = image_handler.process_post_images(post_data)
            
            # Step 3: Add post to export collection
            # This converts content to Mobiledoc, updates image paths,
            # creates tag relationships, and adds to JSON structure
            exporter.add_post(post_data, parser.content, image_mapping)
            
            success_count += 1
            logger.debug(f"Converted: {md_file.name}")
            
        except Exception as e:
            # Log errors but continue processing other files
            logger.error(f"Failed: {md_file.name} - {e}")
            error_count += 1
    
    # Report conversion statistics
    logger.info(f"Success: {success_count}, Failed: {error_count}")
    
    # Step 4: Generate Ghost import JSON file
    json_path: Path = output_dir / "migrate.json"
    exporter.export_to_file(json_path)
    
    # Display output statistics
    stats: dict[str, Any] = exporter.generate_json()
    logger.info(f"Generated: {json_path}")
    logger.info(f"Posts: {len(stats['data']['posts'])}, Tags: {len(stats['data']['tags'])}, Images: {len(image_handler.path_mapping)}")
    
    # Step 5: Create zip package if requested
    if create_zip:
        zip_path: Path = output_dir.parent / f"{output_dir.name}.zip"
        GhostPackager.create_zip(output_dir, zip_path)
        logger.info(f"Package: {zip_path}")
    
    logger.success("Done")


if __name__ == "__main__":
    cli()

