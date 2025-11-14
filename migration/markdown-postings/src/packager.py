"""
Ghost import zip packager

This module creates zip archives containing Ghost import JSON and
associated image files. Ghost can import these zip files directly
through the Admin interface (Settings > Labs > Import).
"""

import zipfile
from pathlib import Path


class GhostPackager:
    """
    Ghost import zip package creator
    
    Packages the Ghost import JSON and images directory into a single
    zip file that can be uploaded to Ghost's import interface.
    
    Expected zip structure:
    - migrate.json (Ghost import JSON)
    - images/ (directory containing image files)
    """

    @staticmethod
    def create_zip(output_dir: Path, zip_path: Path) -> None:
        """
        Create zip archive from output directory
        
        Packages migrate.json and images/ directory into a single zip
        file using DEFLATE compression. The zip structure matches what
        Ghost expects for import.
        
        Args:
            output_dir: Directory containing migrate.json and images/
            zip_path: Path where zip file will be created
        """
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            # Add migrate.json to zip root
            json_file: Path = output_dir / "migrate.json"
            if json_file.exists():
                zf.write(json_file, "migrate.json")
            
            # Add all files from images/ directory
            images_dir: Path = output_dir / "images"
            if images_dir.exists():
                for image_file in images_dir.rglob("*"):
                    if image_file.is_file():
                        # Maintain images/ directory structure in zip
                        arcname: str = str(image_file.relative_to(output_dir))
                        zf.write(image_file, arcname)

