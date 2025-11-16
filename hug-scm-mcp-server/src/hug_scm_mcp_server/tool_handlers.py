"""Tool handlers for individual MCP tools."""

from typing import Any

from .command_executor import CommandExecutor


class ToolHandler:
    """Base class for tool handlers."""

    def __init__(self, executor: CommandExecutor):
        """
        Initialize the tool handler.

        Args:
            executor: Command executor instance
        """
        self.executor = executor

    def handle(self, arguments: dict[str, Any]) -> dict[str, Any]:
        """
        Handle tool execution.

        Args:
            arguments: Tool arguments

        Returns:
            Command execution result
        """
        raise NotImplementedError


class HugHFilesHandler(ToolHandler):
    """Handler for hug_h_files tool."""

    def handle(self, arguments: dict[str, Any]) -> dict[str, Any]:
        """Execute hug h files command."""
        args = ["h", "files"]
        cwd = arguments.get("cwd")

        # Handle mutually exclusive parameters (upstream, temporal, commit, count)
        # Note: These are mutually exclusive in the hug h files command
        if arguments.get("upstream"):
            args.append("-u")
        elif arguments.get("temporal"):
            args.extend(["-t", arguments["temporal"]])
        elif arguments.get("commit"):
            args.append(arguments["commit"])
        elif arguments.get("count"):
            args.append(str(arguments["count"]))

        # show_patch is independent and can be added regardless
        if arguments.get("show_patch"):
            args.append("-p")

        return self.executor.execute(args, cwd)


class HugStatusHandler(ToolHandler):
    """Handler for hug_status tool."""

    def handle(self, arguments: dict[str, Any]) -> dict[str, Any]:
        """Execute hug status command."""
        format_type = arguments.get("format", "short")
        args = ["sl" if format_type == "short" else "s"]
        cwd = arguments.get("cwd")

        return self.executor.execute(args, cwd)


class HugLogHandler(ToolHandler):
    """Handler for hug_log tool."""

    def handle(self, arguments: dict[str, Any]) -> dict[str, Any]:
        """Execute hug log command."""
        args = ["l"]
        cwd = arguments.get("cwd")

        count = arguments.get("count", 10)
        args.extend(["-n", str(count)])

        if arguments.get("oneline"):
            args.append("--oneline")

        if arguments.get("search"):
            args.extend(["--grep", arguments["search"]])

        if arguments.get("file"):
            args.extend(["--", arguments["file"]])

        return self.executor.execute(args, cwd)


class HugBranchListHandler(ToolHandler):
    """Handler for hug_branch_list tool."""

    def handle(self, arguments: dict[str, Any]) -> dict[str, Any]:
        """Execute hug branch list command."""
        args = ["b"]
        cwd = arguments.get("cwd")

        if arguments.get("all"):
            args.append("-a")

        if arguments.get("verbose"):
            args.append("-v")

        return self.executor.execute(args, cwd)


class HugHStepsHandler(ToolHandler):
    """Handler for hug_h_steps tool."""

    def handle(self, arguments: dict[str, Any]) -> dict[str, Any]:
        """Execute hug h steps command."""
        file = arguments.get("file")
        if not file:
            return {
                "success": False,
                "output": "",
                "error": "file parameter is required",
                "exit_code": -1,
            }

        args = ["h", "steps", file]
        cwd = arguments.get("cwd")

        if arguments.get("raw"):
            args.append("--raw")

        return self.executor.execute(args, cwd)


class HugShowDiffHandler(ToolHandler):
    """Handler for hug_show_diff tool."""

    def handle(self, arguments: dict[str, Any]) -> dict[str, Any]:
        """Execute hug show diff command."""
        cwd = arguments.get("cwd")

        # Determine the type of diff to show
        if arguments.get("commit1"):
            # Diff between commits
            args = ["--no-pager", "diff"]
            if arguments.get("stat"):
                args.append("--stat")
            args.append(arguments["commit1"])
            if arguments.get("commit2"):
                args.append(arguments["commit2"])
            if arguments.get("file"):
                args.extend(["--", arguments["file"]])
        elif arguments.get("staged"):
            # Staged changes
            args = ["ss"]
            if arguments.get("file"):
                args.append(arguments["file"])
        else:
            # Unstaged changes (default)
            args = ["sw"]
            if arguments.get("file"):
                args.append(arguments["file"])

        return self.executor.execute(args, cwd)


class ToolRegistry:
    """Registry for managing tool handlers."""

    def __init__(self, executor: CommandExecutor):
        """
        Initialize the tool registry.

        Args:
            executor: Command executor instance
        """
        self.executor = executor
        self._handlers: dict[str, ToolHandler] = {}
        self._register_default_handlers()

    def _register_default_handlers(self) -> None:
        """Register default tool handlers."""
        self.register("hug_h_files", HugHFilesHandler(self.executor))
        self.register("hug_status", HugStatusHandler(self.executor))
        self.register("hug_log", HugLogHandler(self.executor))
        self.register("hug_branch_list", HugBranchListHandler(self.executor))
        self.register("hug_h_steps", HugHStepsHandler(self.executor))
        self.register("hug_show_diff", HugShowDiffHandler(self.executor))

    def register(self, name: str, handler: ToolHandler) -> None:
        """
        Register a tool handler.

        Args:
            name: Tool name
            handler: Tool handler instance
        """
        self._handlers[name] = handler

    def get_handler(self, name: str) -> ToolHandler | None:
        """
        Get a tool handler by name.

        Args:
            name: Tool name

        Returns:
            Tool handler or None if not found
        """
        return self._handlers.get(name)

    def list_tools(self) -> list[str]:
        """
        List all registered tool names.

        Returns:
            List of tool names
        """
        return list(self._handlers.keys())
