"""
Ghost Mobiledoc format converter

This module handles conversion of markdown content to Ghost's Mobiledoc
format. Mobiledoc is Ghost's internal post storage format, which supports
rich content through cards and atoms.
"""

import json
from typing import Any


class MobiledocConverter:
    """
    Converter for Ghost Mobiledoc format
    
    Mobiledoc is a JSON-based document format used by Ghost for storing
    post content. This converter wraps markdown content in a Mobiledoc
    markdown card, which Ghost can render natively.
    
    Ghost supports Mobiledoc version 0.3.1 which includes:
    - markups: inline formatting (bold, italic, etc.)
    - atoms: inline content units
    - cards: block-level content (markdown, html, images, etc.)
    - sections: references to cards/atoms in render order
    """

    VERSION: str = "0.3.1"

    @staticmethod
    def create_mobiledoc(markdown_content: str) -> str:
        """
        Convert markdown content to Mobiledoc JSON string
        
        Creates a Mobiledoc structure with a single markdown card
        containing the full post content. This allows Ghost to
        render the markdown natively without preprocessing.
        
        Args:
            markdown_content: Raw markdown text
            
        Returns:
            JSON string representing Mobiledoc structure
        """
        mobiledoc: dict[str, Any] = {
            "version": MobiledocConverter.VERSION,
            "markups": [],  # No inline markups, handled by markdown
            "atoms": [],    # No inline atoms
            "cards": [
                [
                    "markdown",  # Card type
                    {
                        "cardName": "markdown",
                        "markdown": markdown_content
                    }
                ]
            ],
            "sections": [[10, 0]]  # Section type 10 = card, index 0
        }
        
        return json.dumps(mobiledoc)

    @staticmethod
    def convert_image_paths(content: str, path_mapping: dict[str, str]) -> str:
        """
        Replace Hugo image paths with Ghost image paths in content
        
        Updates all image references in the markdown content to use
        Ghost's /content/images/ path structure. Handles both markdown
        and HTML image syntax.
        
        Args:
            content: Original markdown content with Hugo paths
            path_mapping: Dictionary mapping old paths to new Ghost paths
            
        Returns:
            Content with updated image paths
        """
        converted: str = content
        
        for old_path, new_path in path_mapping.items():
            # Markdown image syntax: ![alt](path)
            converted = converted.replace(f"]({old_path})", f"]({new_path})")
            
            # HTML img tag with double quotes: <img src="path">
            converted = converted.replace(f'src="{old_path}"', f'src="{new_path}"')
            
            # HTML img tag with single quotes: <img src='path'>
            converted = converted.replace(f"src='{old_path}'", f"src='{new_path}'")
        
        return converted

