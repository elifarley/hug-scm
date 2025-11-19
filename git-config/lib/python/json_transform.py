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
                  no_body: bool = False, additional_args: List[str] = None) -> Dict[str, Any]:
    """
    Search commits and return JSON output in GitHub-compatible format.
    
    This uses the same log_json format as git-ll for consistency (DRY principle).
    
    Args:
        search_type: 'message' or 'code'
        search_term: Search term
        with_files: Include file changes (--with-files)
        no_body: Omit commit message body (--no-body)
        additional_args: Additional git log arguments
        
    Returns:
        Dictionary with search results in GitHub-compatible format
    """
    # Use the same format as log_json.py for consistency
    field_sep = '|~|'
    # Format: hash|~|short|~|author_name|~|author_email|~|committer_name|~|committer_email|~|
    #         author_date|~|author_date_rel|~|committer_date|~|committer_date_rel|~|tree|~|
    #         subject|~|body|~|parents|~|refs
    format_str = f"%H{field_sep}%h{field_sep}%an{field_sep}%ae{field_sep}%cn{field_sep}%ce{field_sep}%aI{field_sep}%ar{field_sep}%cI{field_sep}%cr{field_sep}%T{field_sep}%s{field_sep}%B{field_sep}%P{field_sep}%D"
    
    # Build git log command
    cmd = ['git', 'log', f'--format={format_str}']
    
    if with_files:
        cmd.append('--numstat')
    
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
    
    # Import log_json parser for consistency
    try:
        # Add the python lib directory to path
        python_lib_dir = os.path.join(os.path.dirname(__file__))
        if python_lib_dir not in sys.path:
            sys.path.insert(0, python_lib_dir)
        
        from log_json import parse_log_with_stats
        
        # Parse using the same logic as log_json.py
        lines = log_output.split('\n')
        commits = parse_log_with_stats(lines, include_stats=with_files, omit_body=no_body)
        
    except ImportError:
        # Fallback to simple parsing if log_json not available
        commits = []
        for commit_line in log_output.strip().split('\n'):
            if not commit_line or not commit_line.startswith(field_sep.join([''] * 1)[1:]):
                continue
            parts = commit_line.split(field_sep)
            if len(parts) >= 12:
                commits.append({
                    'sha': parts[0],
                    'sha_short': parts[1],
                    'author': {'name': parts[2], 'email': parts[3]},
                    'date': parts[6],
                    'subject': parts[11],
                    'message': parts[12] if len(parts) > 12 else parts[11]
                })
    
    # Build response with search metadata
    return {
        'repository': {
            'path': os.getcwd()
        },
        'timestamp': datetime.now().astimezone().replace(microsecond=0).isoformat().replace('+00:00', 'Z'),
        'command': f'hug {"lf" if search_type == "message" else "lc"} --json',
        'version': os.environ.get('HUG_VERSION', 'unknown'),
        'search': {
            'type': search_type,
            'term': search_term,
            'with_files': with_files,
            'results_count': len(commits)
        },
        'commits': commits  # Use 'commits' key for consistency with log_json
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
            print("Usage: json_transform.py commit_search <type> <term> [--with-files] [--no-body] [git-args...]", file=sys.stderr)
            sys.exit(1)
        search_type = sys.argv[2]
        search_term = sys.argv[3]
        with_files = '--with-files' in sys.argv
        no_body = '--no-body' in sys.argv
        additional_args = [arg for arg in sys.argv[4:] if arg not in ('--with-files', '--no-body')]
        result = commit_search(search_type, search_term, with_files, no_body, additional_args)
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
