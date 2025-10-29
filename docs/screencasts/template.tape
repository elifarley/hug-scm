# VHS Tape Template
# Copy this file to create a new tape for documenting Hug commands
#
# 1. Copy this file: cp template.tape hug-<command>.tape
# 2. Update the Output line with your desired output filename
# 3. Adjust terminal dimensions as needed
# 4. Add your command demonstrations between Setup and Cleanup
# 5. Test with: vhs hug-<command>.tape
# 6. Build all tapes with: make vhs

# Output file (GIF or PNG)
# For GIF: Output ../commands/img/hug-<command>.gif
# For PNG: Output ../commands/img/hug-<command>.png
Output ../commands/img/hug-COMMAND.gif

Require echo
Require hug

# Terminal settings
Set Shell "fish"
Set FontSize 13        # Readable size
Set Width 1020         # Standard width for docs
Set Height 600         # Adjust based on output length
Set Margin 0
Set Padding 10
Set Theme "Afterglow"  # Consistent theme

#==============================================================================
# Setup (hidden from output)
#==============================================================================
Hide

# Navigate to demo repository
Type "cd /tmp/demo-repo" Enter
Sleep 500ms

# Optional: Clean slate
Type "hug w zap-all -f" Enter
Sleep 500ms

# Optional: Create specific setup (branches, files, commits, etc.)
# Type "setup commands here" Enter
# Sleep 500ms

# Clear screen before showing
Type "clear" Enter
Sleep 200ms

Show

#==============================================================================
# Command Demonstration (visible in output)
#==============================================================================

# Set typing speed for visible commands
Set TypingSpeed 40ms

# Demonstrate your command
Type "hug <command>  # Description of what this does" Enter
Sleep 2s

# Optional: Show related commands or state changes
Type@0s "" Enter  # Empty line for spacing
Type "hug <another-command>  # Related command" Enter
Sleep 2s

# Optional: For PNG screenshots, capture at the right moment
# Screenshot ../commands/img/hug-COMMAND.png

#==============================================================================
# Cleanup (hidden from output)
#==============================================================================
Hide

# Reset to clean state
Type "hug w zap-all -f" Enter
Sleep 300ms

# Optional: Delete created branches, reset HEAD, etc.
# Type "cleanup commands here" Enter
# Sleep 300ms

#==============================================================================
# Notes and Tips
#==============================================================================
# 
# Timing Guidelines:
# - Sleep 200ms-500ms  : Between setup commands
# - Sleep 1s-2s        : For reading short output
# - Sleep 2s-3s        : For reading detailed output
# - Sleep 300ms        : After cleanup commands
#
# Typing Speed:
# - Set TypingSpeed 40ms : Natural typing speed
# - Type@60ms "text"     : Slower typing for emphasis
# - Type@0ms "text"      : Instant typing for setup
#
# Dimension Guidelines:
# - Height 280-400px   : Simple commands (1-5 lines output)
# - Height 600-800px   : Detailed commands (multiple sections)
# - Height 1000px+     : Workflows (multiple commands)
#
# Output Types:
# - .gif : Animated, good for workflows and demonstrations
# - .png : Static screenshot, good for single command output
#
# For multiple screenshots from one tape:
# Output file1.png
# Type "command1" Enter
# Screenshot file1.png
# 
# Output file2.png  
# Type "command2" Enter
# Screenshot file2.png
#
