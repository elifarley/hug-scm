#!/usr/bin/env python3
"""
JSON transformation utilities for Hug SCM

This module provides Python-based JSON transformation helpers for complex
operations that are difficult or inefficient in pure Bash.

Usage:
    python3 json_transform.py transform_git_log <log_output>
    python3 json_transform.py transform_git_status <status_output>
    python3 json_transform.py commit_search <search_type> <search_term> [--with-files]
"""

import sys
import json
import subprocess
import os
from datetime import datetime
from typing import Dict, List, Any, Optional


def transform_git_log_to_json(log_output: str, with_files: bool = False) -> str:
    """
    Transform git log output to JSON with proper types.
    
    Args:
        log_output: Git log output with NUL-separated commits
        with_files: Whether to include file information
        
    Returns:
        JSON string with properly typed commit data
    """
    commits = []
    for line in log_output.strip().split('\0'):
        if not line:
            continue
        fields = line.split('---HUG-FIELD-SEPARATOR---')
        if len(fields) < 6:
            continue
            
        commit = {
            'sha': fields[0],
            'sha_short': fields[1],
            'author': {
                'name': fields[2],
                'email': fields[3]
            },
            'date': fields[4],
            'message': fields[5]
        }
        
        if with_files and len(fields) > 6:
            commit['files'] = json.loads(fields[6]) if fields[6] else []
            
        commits.append(commit)
    
    return json.dumps(commits, ensure_ascii=False, indent=2)


def transform_git_status_to_json(status_output: str) -> Dict[str, Any]:
    """
    Transform git status output to JSON with proper types.
    
    Args:
        status_output: Git status output (short format)
        
    Returns:
        Dictionary with properly typed status data
    """
    staged = []
    unstaged = []
    untracked = []
    
    # Don't strip individual lines - git status format requires exact character positions
    for line in status_output.split('\n'):
        if not line:
            continue
            
        status_code = line[:2]
        file_path = line[3:] if len(line) > 3 else ''
        
        # Staged changes (first character)
        if status_code[0] not in (' ', '?', '!'):
            staged.append({
                'path': file_path,
                'status': _status_to_type(status_code[0])
            })
        
        # Unstaged changes (second character)
        if status_code[1] not in (' ', '?', '!'):
            unstaged.append({
                'path': file_path,
                'status': _status_to_type(status_code[1])
            })
        
        # Untracked files
        if status_code == '??':
            untracked.append({
                'path': file_path,
                'status': 'untracked'
            })
    
    return {
        'staged': staged,
        'unstaged': unstaged,
        'untracked': untracked,
        'summary': {
            'staged_count': len(staged),
            'unstaged_count': len(unstaged),
            'untracked_count': len(untracked),
            'clean': len(staged) == 0 and len(unstaged) == 0
        }
    }


def _status_to_type(code: str) -> str:
    """Convert git status code to human-readable type."""
    mapping = {
        'M': 'modified',
        'A': 'added',
        'D': 'deleted',
        'R': 'renamed',
        'C': 'copied',
        'U': 'conflict',
        'T': 'type_changed'
    }
    return mapping.get(code, 'unknown')


def validate_json_schema(json_data: str, schema_name: str) -> bool:
    """
    Validate JSON against a predefined schema.
    
    Args:
        json_data: JSON string to validate
        schema_name: Name of schema to validate against
        
    Returns:
        True if valid, False otherwise
    """
    try:
        data = json.loads(json_data)
    except json.JSONDecodeError:
        return False
    
    # Basic validation for common schemas
    if schema_name == 'status':
        required_keys = ['repository', 'status']
        return all(key in data for key in required_keys)
    elif schema_name == 'commit_search':
        required_keys = ['repository', 'search', 'results']
        return all(key in data for key in required_keys)
    elif schema_name == 'branch_list':
        required_keys = ['repository', 'branches']
        return all(key in data for key in required_keys)
    
    return True


def commit_search(search_type: str, search_term: str, with_files: bool = False, 
                  additional_args: List[str] = None) -> Dict[str, Any]:
    """
    Search commits and return JSON output.
    
    This replaces the complex bash parsing in output_json_commit_search.
    
    Args:
        search_type: 'message' or 'code'
        search_term: Search term
        with_files: Include file changes
        additional_args: Additional git log arguments
        
    Returns:
        Dictionary with search results
    """
    # Build git log command
    # Format: full_hash NULL short_hash NULL author_name NULL author_email NULL date NULL subject NULL
    cmd = ['git', 'log', '--format=%H%x00%h%x00%an%x00%ae%x00%ai%x00%s%x00']
    
    if search_type == 'message':
        cmd.append(f'--grep={search_term}')
    elif search_type == 'code':
        cmd.append(f'-S{search_term}')
    else:
        return {
            'error': {
                'type': 'invalid_search_type',
                'message': 'Search type must be "message" or "code"'
            }
        }
    
    if additional_args:
        cmd.extend(additional_args)
    
    try:
        # Execute git log
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        log_output = result.stdout
    except subprocess.CalledProcessError as e:
        return {
            'error': {
                'type': 'git_error',
                'message': f'Git command failed: {e.stderr}'
            }
        }
    
    # Parse commits
    commits = []
    # Split by newline first, then by NULL
    for commit_line in log_output.strip().split('\n'):
        if not commit_line:
            continue
        
        # Split by NULL separator
        parts = commit_line.split('\x00')
        if len(parts) < 6:
            continue
        
        commit = {
            'sha': parts[0],
            'sha_short': parts[1],
            'author': {
                'name': parts[2],
                'email': parts[3]
            },
            'date': parts[4],
            'message': parts[5]
        }
        
        # Get files if requested
        if with_files and parts[0]:
            try:
                files_result = subprocess.run(
                    ['git', 'show', '--name-status', '--format=', parts[0]],
                    capture_output=True, text=True, check=True
                )
                files = []
                for file_line in files_result.stdout.strip().split('\n'):
                    if not file_line:
                        continue
                    parts_file = file_line.split('\t', 1)
                    if len(parts_file) == 2:
                        status_code = parts_file[0][0] if parts_file[0] else 'M'
                        files.append({
                            'path': parts_file[1],
                            'status': _status_to_type(status_code)
                        })
                commit['files'] = files
            except subprocess.CalledProcessError:
                commit['files'] = []
        
        commits.append(commit)
    
    # Build response
    return {
        'repository': {
            'path': os.getcwd()
        },
        'timestamp': datetime.now().astimezone().replace(microsecond=0).isoformat().replace('+00:00', 'Z'),
        'command': 'hug lf --json' if search_type == 'message' else 'hug lc --json',
        'version': os.environ.get('HUG_VERSION', 'unknown'),
        'search': {
            'type': search_type,
            'term': search_term,
            'with_files': with_files,
            'results_count': len(commits)
        },
        'results': commits
    }


def main():
    """CLI entry point for JSON transformations."""
    if len(sys.argv) < 2:
        print("Usage: json_transform.py <command> [args...]", file=sys.stderr)
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == 'transform_git_log':
        log_data = sys.stdin.read()
        with_files = '--with-files' in sys.argv
        result = transform_git_log_to_json(log_data, with_files)
        print(result)
    elif command == 'transform_git_status':
        status_data = sys.stdin.read()
        result = json.dumps(transform_git_status_to_json(status_data), indent=2)
        print(result)
    elif command == 'commit_search':
        if len(sys.argv) < 4:
            print("Usage: json_transform.py commit_search <type> <term> [--with-files] [git-args...]", file=sys.stderr)
            sys.exit(1)
        search_type = sys.argv[2]
        search_term = sys.argv[3]
        with_files = '--with-files' in sys.argv
        additional_args = [arg for arg in sys.argv[4:] if arg != '--with-files']
        result = commit_search(search_type, search_term, with_files, additional_args)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    elif command == 'validate':
        if len(sys.argv) < 3:
            print("Usage: json_transform.py validate <schema_name>", file=sys.stderr)
            sys.exit(1)
        json_data = sys.stdin.read()
        schema_name = sys.argv[2]
        if validate_json_schema(json_data, schema_name):
            sys.exit(0)
        else:
            sys.exit(1)
    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
