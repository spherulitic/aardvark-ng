import os
import argparse

def rename_files(base_dir, execute=False):
    base_dir = os.path.abspath(base_dir)
    for root, _, files in os.walk(base_dir):
        # Determine the relative path from the base directory
        relative_path = os.path.relpath(root, base_dir)
        parts = relative_path.split(os.sep)

        # Skip if the relative path doesn't contain at least one directory
        if len(parts) < 1:
            continue

        year_dir = parts[0]  # The first directory after the base directory

        # Skip directories that don't have a valid year or are older than 2006
        if not year_dir.isdigit() or int(year_dir) < 2006:
            continue

        for file in files:
            # Check if the file ends with '.ST4'
            if file.endswith('.STA'):
                old_path = os.path.join(root, file)
                new_path = os.path.join(root, file[:-4] + '.ST4')

                if execute:
                    try:
                        os.rename(old_path, new_path)
                        print(f"Renamed: {old_path} -> {new_path}")
                    except OSError as e:
                        print(f"WARNING: could not rename {old_path}: {e}")
                else:
                    print(f"Will rename: {old_path} -> {new_path}")

def main():
    parser = argparse.ArgumentParser(description="Recursively rename .STA files to .ST4.")
    parser.add_argument("base_dir", help="Base directory to start the search.")
    parser.add_argument("--execute", action="store_true", help="Actually perform the renaming.")

    args = parser.parse_args()

    rename_files(args.base_dir, execute=args.execute)

if __name__ == "__main__":
    main()

