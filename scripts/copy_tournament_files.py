import os
import shutil
import argparse
from pathlib import Path

def is_valid_year_dir(directory_name):
    """Check if the directory name is a valid year."""
    return directory_name.isdigit() and int(directory_name) >= 1993 

def copy_year_dirs(src, dst, execute):
    """Copy year-based directories from src to dst."""
    src_path = Path(src).resolve()
    dst_path = Path(dst).resolve()

    if not src_path.is_dir():
        print(f"Source directory {src} does not exist or is not a directory.")
        return

    if not dst_path.exists():
        print(f"Destination directory {dst} does not exist. Creating it.")
        if execute:
            dst_path.mkdir(parents=True, exist_ok=True)

    for item in src_path.iterdir():
        if item.is_dir() and is_valid_year_dir(item.name):
            src_dir = item
            dst_dir = dst_path / src_dir.name

            if not dst_dir.exists():
                print(f"Creating directory: {dst_dir}")
                if execute:
                    dst_dir.mkdir(parents=True, exist_ok=True)

            for sub_item in src_dir.rglob("*"):
                relative_path = sub_item.relative_to(src_dir)
                dst_file = dst_dir / relative_path

                if sub_item.is_file():
                    print(f"Copying {sub_item} to {dst_file}")
                    if execute:
                        dst_file.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(sub_item, dst_file)
    if execute:
        print("Finished actual execution of copying")
    else:
        print("Finished dry run")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Copy year-based directories >= 1993 from src to dst.")
    parser.add_argument("src", type=str, help="Source directory")
    parser.add_argument("dst", type=str, help="Destination directory")
    parser.add_argument("--execute", action="store_true", help="Actually perform the copying.")

    args = parser.parse_args()

    copy_year_dirs(args.src, args.dst, args.execute)

