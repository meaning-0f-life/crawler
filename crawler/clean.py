#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Cleanup script for document crawler project."""

import os
import sys
import shutil
import subprocess
import argparse
from pathlib import Path

try:
    import psycopg2
except ImportError:
    psycopg2 = None


def run_cmd(cmd, cwd=None):
    """Run shell command."""
    try:
        if isinstance(cmd, str):
            cmd = cmd.split()
        result = subprocess.run(cmd, cwd=cwd or Path.cwd(), capture_output=True, text=True)
        return result
    except Exception as e:
        print(f"Error: {e}")
        return None


def docker_available():
    """Check if Docker is available."""
    return run_cmd(['docker', '--version']) and run_cmd(['docker', '--version']).returncode == 0


def stop_containers():
    """Stop and remove Docker containers."""
    print("\n" + "=" * 60)
    print("Stopping Docker containers...")
    print("=" * 60)
    
    if not Path('docker-compose.yml').exists():
        print("docker-compose.yml not found. Skipping.")
        return True
    
    # Try v2 first
    result = run_cmd(['docker', 'compose', 'down', '-v'])
    if result and result.returncode == 0:
        print("Containers stopped.")
        return True
    
    # Try legacy
    result = run_cmd(['docker-compose', 'down', '-v'])
    if result and result.returncode == 0:
        print("Containers stopped.")
        return True
    
    print("Failed to stop containers.")
    return False


def remove_volume(keep_data=False):
    """Remove PostgreSQL Docker volume."""
    if keep_data:
        print("\nSkipping database volume (--keep-data).")
        return True
    
    print("\n" + "=" * 60)
    print("Removing PostgreSQL volume...")
    print("=" * 60)
    
    volume = 'postgres_data'
    result = run_cmd(['docker', 'volume', 'ls', '-q', '--filter', f'name={volume}'])
    if not result or not result.stdout.strip():
        print(f"Volume '{volume}' not found.")
        return True
    
    result = run_cmd(['docker', 'volume', 'rm', volume])
    if result and result.returncode == 0:
        print(f"Volume '{volume}' removed.")
        return True
    
    print(f"Failed to remove volume '{volume}'.")
    return False


def cleanup_containers():
    """Remove stopped containers."""
    print("\n" + "=" * 60)
    print("Cleaning up stopped containers...")
    print("=" * 60)
    
    containers = ['document_postgres', 'document_crawler', 'document_importer', 'document_pgadmin']
    
    for container in containers:
        result = run_cmd(['docker', 'ps', '-a', '-q', '--filter', f'name={container}'])
        if result and result.stdout.strip():
            run_cmd(['docker', 'rm', '-f', container])
            print(f"Removed container: {container}")
        else:
            print(f"Container not found: {container}")
    
    return True


def remove_local_database():
    """Remove local PostgreSQL database if it exists."""
    print("\n" + "=" * 60)
    print("Removing local PostgreSQL database...")
    print("=" * 60)
    
    if psycopg2 is None:
        print("psycopg2 not installed. Skipping local database removal.")
        print("Install it with: pip install psycopg2-binary")
        return True
    
    db_config = {
        'host': 'localhost',
        'port': 5432,
        'database': 'postgres',  # Connect to postgres database to drop document_index
        'user': 'postgres',
        'password': 'postgres'
    }
    
    db_name = 'document_index'
    
    try:
        conn = psycopg2.connect(**db_config)
        conn.autocommit = True
        cursor = conn.cursor()
        
        # Check if database exists
        cursor.execute("SELECT 1 FROM pg_database WHERE datname = %s", (db_name,))
        exists = cursor.fetchone()
        
        if exists:
            # Terminate connections to the database
            cursor.execute(f"""
                SELECT pg_terminate_backend(pid)
                FROM pg_stat_activity
                WHERE datname = %s AND pid <> pg_backend_pid()
            """, (db_name,))
            
            # Drop database
            db_name_quoted = psycopg2.extensions.quote_ident(db_name, conn)
            cursor.execute(f"DROP DATABASE {db_name_quoted}")
            print(f"Database '{db_name}' removed.")
        else:
            print(f"Database '{db_name}' not found.")
        
        cursor.close()
        conn.close()
        return True
    
    except psycopg2.Error as e:
        print(f"Error connecting to PostgreSQL: {e}")
        print("Make sure PostgreSQL is running and accessible.")
        return True  # Don't fail cleanup if database is not accessible


def clear_dir(dir_path, desc):
    """Clear directory contents."""
    path = Path(dir_path)
    
    if not path.exists():
        print(f"{desc} directory '{dir_path}' not found.")
        return True
    
    if not path.is_dir():
        print(f"{desc} path '{dir_path}' is not a directory.")
        return True
    
    print(f"\nClearing {desc.lower()}: {dir_path}")
    
    try:
        items = list(path.iterdir())
        if not items:
            print("  Already empty.")
            return True
        
        for item in items:
            try:
                if item.is_file() or item.is_symlink():
                    item.unlink()
                else:
                    shutil.rmtree(item)
            except Exception as e:
                print(f"  Warning: Failed to remove {item.name}: {e}")
        
        print(f"  Removed {len(items)} items.")
        return True
    
    except Exception as e:
        print(f"Error clearing '{dir_path}': {e}")
        return False


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Clean up document crawler project',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python clean.py                    # Full cleanup
  python clean.py --keep-data        # Keep database
  python clean.py --keep-storage     # Keep storage files
  python clean.py --keep-output      # Keep output files
        """
    )
    parser.add_argument('--keep-data', action='store_true', help='Keep database volume')
    parser.add_argument('--keep-storage', action='store_true', help='Keep storage/ directory')
    parser.add_argument('--keep-output', action='store_true', help='Keep output/ directory')
    
    args = parser.parse_args()
    
    print("=" * 60)
    print("Document Crawler Cleanup")
    print("=" * 60)
    
    # Check directory
    if not Path('docker-compose.yml').exists() and not Path('crawler').exists():
        print("\nWarning: Run from project root directory.")
        response = input("Continue? (y/N): ").strip().lower()
        if response != 'y':
            print("Aborted.")
            return 1
    
    success = True
    
    # Docker cleanup
    if docker_available():
        if not stop_containers():
            success = False
        if not cleanup_containers():
            success = False
        if not remove_volume(args.keep_data):
            success = False
    else:
        print("\n" + "=" * 60)
        print("Docker not available. Skipping Docker cleanup.")
        print("=" * 60)
        print("\nIf using external PostgreSQL:")
        print("  psql -U postgres -c 'DROP DATABASE document_index;'")
    
    # Remove local database if not keeping data
    if not args.keep_data:
        if not remove_local_database():
            success = False
    else:
        print("\nSkipping local database (--keep-data).")
    
    # Clear directories
    if not args.keep_storage:
        if not clear_dir('storage', 'Storage'):
            success = False
    else:
        print("\nSkipping storage/ (--keep-storage).")
    
    if not args.keep_output:
        if not clear_dir('output', 'Output'):
            success = False
    else:
        print("\nSkipping output/ (--keep-output).")
    
    print("\n" + "=" * 60)
    print("Cleanup completed!" if success else "Cleanup finished with warnings.")
    print("=" * 60)
    
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
