#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Designer Skills Installer for Claude Code
# Installs skills and commands into any Claude Code project.
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="1.0.0"

ALL_PLUGINS=(
  design-ops
  design-research
  design-systems
  designer-toolkit
  interaction-design
  prototyping-testing
  ui-design
  ux-strategy
)

# ── Defaults ──────────────────────────────────────────────────
TARGET=""
PLUGINS=()
LIST_MODE=false
UNINSTALL=false
GLOBAL=false

# ── Usage ─────────────────────────────────────────────────────
usage() {
  cat <<'USAGE'
Designer Skills Installer v1.0.0

Usage:
  ./install.sh [options] [target-directory]

Options:
  -g, --global           Install to ~/.claude/ (available in all sessions).
                         Without this flag, installs to a project directory.
  -p, --plugin <name>    Install specific plugin(s). Repeat for multiple.
                         If omitted, all 8 plugins are installed.
  -l, --list             List available plugins and exit.
  -u, --uninstall        Remove designer-skills from the target.
  -h, --help             Show this help message.

Examples:
  ./install.sh -g                       # Install all plugins globally
  ./install.sh -g -p ui-design          # Install one plugin globally
  ./install.sh ~/my-project             # Install into a specific project
  ./install.sh -p ui-design -p ux-strategy ~/my-project
  ./install.sh -u -g                    # Uninstall globally
  ./install.sh -u ~/my-project          # Uninstall from a project
  ./install.sh -l                       # List available plugins

After install, commands are available as slash commands in Claude Code:
  Global:  /user:design-research/discover
  Project: /project:design-research/discover
USAGE
}

# ── Parse args ────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--plugin)
      PLUGINS+=("$2")
      shift 2
      ;;
    -g|--global)
      GLOBAL=true
      shift
      ;;
    -l|--list)
      LIST_MODE=true
      shift
      ;;
    -u|--uninstall)
      UNINSTALL=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Error: Unknown option $1" >&2
      usage
      exit 1
      ;;
    *)
      TARGET="$1"
      shift
      ;;
  esac
done

# ── List mode ─────────────────────────────────────────────────
if $LIST_MODE; then
  echo "Available plugins:"
  echo ""
  for plugin in "${ALL_PLUGINS[@]}"; do
    desc=$(python3 -c "import json; print(json.load(open('$SCRIPT_DIR/$plugin/.claude-plugin/plugin.json'))['description'])" 2>/dev/null || echo "")
    skill_count=$(find "$SCRIPT_DIR/$plugin/skills" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
    cmd_count=$(find "$SCRIPT_DIR/$plugin/commands" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    printf "  %-24s %2s skills, %s commands\n" "$plugin" "$skill_count" "$cmd_count"
    if [[ -n "$desc" ]]; then
      printf "    %s\n" "$desc"
    fi
    echo ""
  done
  exit 0
fi

# ── Resolve target ────────────────────────────────────────────
if $GLOBAL; then
  TARGET="$HOME"
  SCOPE="user"
else
  TARGET="${TARGET:-.}"
  TARGET="$(cd "$TARGET" && pwd)"
  SCOPE="project"
fi

if [[ ! -d "$TARGET" ]]; then
  echo "Error: Target directory does not exist: $TARGET" >&2
  exit 1
fi

# ── Uninstall ─────────────────────────────────────────────────
if $UNINSTALL; then
  if $GLOBAL; then
    echo "Uninstalling designer-skills from ~/.claude/ ..."
  else
    echo "Uninstalling designer-skills from $TARGET ..."
  fi
  removed=0

  for plugin in "${ALL_PLUGINS[@]}"; do
    if [[ -d "$TARGET/.claude/commands/$plugin" ]]; then
      rm -rf "$TARGET/.claude/commands/$plugin"
      removed=$((removed + 1))
    fi
    if [[ -d "$TARGET/.claude/designer-skills/$plugin" ]]; then
      rm -rf "$TARGET/.claude/designer-skills/$plugin"
      removed=$((removed + 1))
    fi
  done

  # Clean up empty parent dirs
  rmdir "$TARGET/.claude/commands" 2>/dev/null || true
  rmdir "$TARGET/.claude/designer-skills" 2>/dev/null || true

  if [[ $removed -gt 0 ]]; then
    echo "Done. Removed designer-skills files."
  else
    echo "Nothing to remove — designer-skills not found in $TARGET"
  fi
  exit 0
fi

# ── Resolve plugins ──────────────────────────────────────────
if [[ ${#PLUGINS[@]} -eq 0 ]]; then
  PLUGINS=("${ALL_PLUGINS[@]}")
fi

# Validate plugin names
for plugin in "${PLUGINS[@]}"; do
  found=false
  for valid in "${ALL_PLUGINS[@]}"; do
    if [[ "$plugin" == "$valid" ]]; then
      found=true
      break
    fi
  done
  if ! $found; then
    echo "Error: Unknown plugin '$plugin'" >&2
    echo "Run ./install.sh -l to see available plugins." >&2
    exit 1
  fi
done

# ── Install ───────────────────────────────────────────────────
COMMANDS_DIR="$TARGET/.claude/commands"
SKILLS_DIR="$TARGET/.claude/designer-skills"

total_skills=0
total_commands=0

if $GLOBAL; then
  echo "Installing designer-skills globally (~/.claude/) ..."
else
  echo "Installing designer-skills into $TARGET ..."
fi
echo ""

for plugin in "${PLUGINS[@]}"; do
  plugin_skills=0
  plugin_commands=0

  # ── Install skills ──
  if [[ -d "$SCRIPT_DIR/$plugin/skills" ]]; then
    mkdir -p "$SKILLS_DIR/$plugin"
    for skill_dir in "$SCRIPT_DIR/$plugin/skills"/*/; do
      [[ -d "$skill_dir" ]] || continue
      skill_name=$(basename "$skill_dir")
      if [[ -f "$skill_dir/SKILL.md" ]]; then
        cp "$skill_dir/SKILL.md" "$SKILLS_DIR/$plugin/$skill_name.md"
        plugin_skills=$((plugin_skills + 1))
      fi
    done
  fi

  # ── Install commands ──
  if [[ -d "$SCRIPT_DIR/$plugin/commands" ]]; then
    mkdir -p "$COMMANDS_DIR/$plugin"
    for cmd_file in "$SCRIPT_DIR/$plugin/commands"/*.md; do
      [[ -f "$cmd_file" ]] || continue
      cmd_name=$(basename "$cmd_file")
      target_file="$COMMANDS_DIR/$plugin/$cmd_name"

      # Copy command file
      cp "$cmd_file" "$target_file"

      # Append skill resolution instructions
      if $GLOBAL; then
        skills_path="~/.claude/designer-skills/$plugin"
      else
        skills_path=".claude/designer-skills/$plugin"
      fi
      cat >> "$target_file" <<FOOTER

---
## Skill Resolution
When this command references a skill by name (e.g. \`skill-name\` skill), read the full skill definition from \`$skills_path/skill-name.md\` before applying it. Each skill file contains domain context, detailed instructions, and methodology that you must follow.
FOOTER

      plugin_commands=$((plugin_commands + 1))
    done
  fi

  total_skills=$((total_skills + plugin_skills))
  total_commands=$((total_commands + plugin_commands))
  printf "  %-24s %2d skills, %d commands\n" "$plugin" "$plugin_skills" "$plugin_commands"
done

echo ""
echo "Installed $total_skills skills and $total_commands commands."
echo ""
echo "Commands are now available in Claude Code as slash commands:"
echo ""

for plugin in "${PLUGINS[@]}"; do
  if [[ -d "$COMMANDS_DIR/$plugin" ]]; then
    for cmd_file in "$COMMANDS_DIR/$plugin"/*.md; do
      [[ -f "$cmd_file" ]] || continue
      cmd_name=$(basename "$cmd_file" .md)
      echo "  /$SCOPE:$plugin/$cmd_name"
    done
  fi
done

echo ""
echo "Done."
