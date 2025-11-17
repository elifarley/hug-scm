---
title: Examples
---

# Example Usage Session

Here's a complete example of an AI assistant helping investigate a repository using the Hug SCM MCP Server:

## Session Transcript

**User**: "I need to understand this repository"

**Assistant**: "I'll help you explore this repository. Let me start by checking its status."

*[Assistant calls hug_status with format="short"]*

**Result**: Shows 3 modified files, 2 staged files, 1 untracked file

**Assistant**: "The repository has some uncommitted work:
- 3 files have been modified
- 2 files are staged for commit
- 1 new file hasn't been tracked yet

Let me check the recent commit history to understand what's been happening."

*[Assistant calls hug_log with count=10]*

**Result**: Displays last 10 commits with messages, authors, and dates

**User**: "What files have changed in the last week?"

**Assistant**: "Let me check what files were modified in the past week."

*[Assistant calls hug_h_files with temporal="1 week ago"]*

**Result**: Lists 15 files with line change statistics

**Assistant**: "In the last week, 15 files were modified across 23 commits. The most active files are:
- src/server.py (+150, -45 lines)
- tests/test_server.py (+200, -10 lines)
- README.md (+80, -5 lines)

Would you like to see the changes in any specific file?"

**User**: "Yes, show me what changed in src/server.py"

**Assistant**: "Let me get the diff for that file."

*[Assistant calls hug_show_diff with file="src/server.py"]*

**Result**: Shows unified diff of changes in src/server.py

**Assistant**: "The changes to src/server.py include:
- Added new error handling functions
- Refactored the command execution logic
- Added support for timeout configuration

The file has grown by about 105 lines net."

**User**: "When was this file last modified?"

**Assistant**: "Let me check that."

*[Assistant calls hug_h_steps with file="src/server.py"]*

**Result**: "src/server.py was last modified 2 commits ago"

**Assistant**: "The src/server.py file was last modified 2 commits ago in commit abc123. That was approximately 3 hours ago."

**User**: "Are there any local commits that haven't been pushed?"

**Assistant**: "Let me check what commits are local-only."

*[Assistant calls hug_h_files with upstream=true]*

**Result**: Shows 8 files affected by 5 local commits

**Assistant**: "Yes, you have 5 local commits that haven't been pushed yet. These commits affect 8 files:
- src/server.py
- tests/test_server.py
- README.md
- USAGE.md
- pyproject.toml
- src/__init__.py
- tests/conftest.py
- Makefile

Would you like me to show you what these commits are about?"

**User**: "Yes, show me those commits"

**Assistant**: *[Calls hug_log with count=5]*

**Result**: Shows the 5 unpushed commits

**Assistant**: "Your 5 unpushed commits are:
1. 'Add comprehensive error handling' (2 hours ago)
2. 'Refactor command execution' (3 hours ago)
3. 'Add timeout configuration' (4 hours ago)
4. 'Update documentation' (5 hours ago)
5. 'Add usage examples' (6 hours ago)

These all look like good progress on improving the server reliability and documentation."

**User**: "What branches exist in this project?"

**Assistant**: *[Calls hug_branch_list with all=true, verbose=true]*

**Result**: Lists all branches with their last commit info

**Assistant**: "The project has several branches:
- * main (current): Last commit 2 hours ago
- feature/error-handling: Last commit 1 day ago
- feature/performance: Last commit 3 days ago
- origin/main: Last commit 1 day ago (you're ahead by 5 commits)
- origin/feature/performance: Last commit 3 days ago

You're currently on 'main' and it's ahead of 'origin/main' by those 5 commits we discussed."

## Key Takeaways from This Session

1. **Start with Status**: Always begin by understanding the current state
2. **Build Context Progressively**: Move from high-level (status) to specific (file diffs)
3. **Use Time-Based Queries**: Temporal filters help understand recent activity
4. **Combine Tools**: Different tools complement each other for complete understanding
5. **Answer Questions Directly**: The MCP server enables answering specific questions about repository state

## Other Common Scenarios

### Debugging a Production Issue

```
1. hug_log (search="hotfix", count=20) - Find recent fixes
2. hug_h_files (temporal="2 days ago") - See recent changes
3. hug_show_diff (commit1="prod-tag", commit2="HEAD") - Compare with production
4. hug_h_steps (file="critical_module.py") - When was critical file changed
```

### Code Review Preparation

```
1. hug_h_files (upstream=true, show_patch=true) - Review all changes to push
2. hug_log (count=N) - Review commit messages
3. hug_show_diff (staged=true) - Check staged changes
4. hug_status (format="long") - Verify nothing is forgotten
```

### Onboarding to New Project

```
1. hug_branch_list (all=true, verbose=true) - Understand branch structure
2. hug_log (count=50) - Recent development history
3. hug_h_files (temporal="1 month ago") - Active areas of development
4. hug_log (file="main.py") - Evolution of key files
```

### Investigating Test Failures

```
1. hug_log (search="test", count=20) - Find test-related commits
2. hug_h_files (temporal="1 day ago") - What changed recently
3. hug_show_diff (file="tests/test_failing.py") - Check test changes
4. hug_h_steps (file="tests/test_failing.py") - When test was last modified
```
