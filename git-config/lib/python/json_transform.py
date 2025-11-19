#!/usr/bin/env python3
"""
JSON transformation utilities for Hug SCM

This module provides Python-based JSON transformation helpers for complex
operations that are difficult or inefficient in pure Bash.

Usage:
    python3 json_transform.py transform_git_log <log_output>
    python3 json_transform.py transform_git_status <status_output>
"""

import sys
import json
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
    
    for line in status_output.strip().split('\n'):
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
