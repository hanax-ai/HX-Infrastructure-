import sys
import pathlib

# Resolve the project root directory (which is 'gateway/')
project_root = pathlib.Path(__file__).resolve().parents[1]

# Add the project root to the Python path if it's not already there.
# This allows tests to import modules from 'src.*' as if they were top-level.
project_root_path = str(project_root)
if project_root_path not in sys.path:
    sys.path.insert(0, project_root_path)

