#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TASK_FILE="$SCRIPT_DIR/task.md"
LEADER_PROMPT="$SCRIPT_DIR/leader.md"
DEVELOPER_PROMPT="$SCRIPT_DIR/developer.md"
REVIEWER_PROMPT="$SCRIPT_DIR/reviewer.md"
QA_PROMPT="$SCRIPT_DIR/qa.md"
OUTPUT_DIR="$SCRIPT_DIR/output"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

# Check prerequisites
if ! command -v claude &> /dev/null; then
    echo -e "${RED}Error: 'claude' CLI not found. Install Claude Code first.${NC}"
    exit 1
fi

# Check task file has content
TASK_CONTENT=$(cat "$TASK_FILE")
if echo "$TASK_CONTENT" | grep -q "^<!-- Describe your task here"; then
    echo -e "${RED}Error: Please fill in the task description in agents/task.md before running.${NC}"
    echo -e "${YELLOW}Edit: $TASK_FILE${NC}"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RUN_DIR="$OUTPUT_DIR/$TIMESTAMP"
mkdir -p "$RUN_DIR"

echo -e "${GREEN}Agent Harness — 4-Agent Pipeline${NC}"
echo -e "Project: ${BLUE}$PROJECT_DIR${NC}"
echo -e "Run:     ${BLUE}$RUN_DIR${NC}"
echo ""

# ─────────────────────────────────────────────
# Phase 1: Leader (Architect)
# ─────────────────────────────────────────────
header "Phase 1/4: LEADER — Analyzing & Planning"

LEADER_SYSTEM=$(cat "$LEADER_PROMPT")

LEADER_INPUT="$LEADER_SYSTEM

---

## Task to Analyze

$TASK_CONTENT

---

## Current Git State
Branch: $(cd "$PROJECT_DIR" && git branch --show-current)
Modified files:
$(cd "$PROJECT_DIR" && git diff --name-only HEAD)

Recent commits:
$(cd "$PROJECT_DIR" && git log --oneline -5)

Analyze this task, read the relevant files, and produce your implementation plan."

echo "$LEADER_INPUT" | claude --print \
    --allowedTools "Read,Glob,Grep,Bash(git diff:*),Bash(git log:*),Bash(git show:*)" \
    -p "$LEADER_INPUT" \
    > "$RUN_DIR/01_leader_plan.md" 2>&1

echo -e "${GREEN}Leader plan saved to: $RUN_DIR/01_leader_plan.md${NC}"

# ─────────────────────────────────────────────
# Phase 2: Developer (Implementation)
# ─────────────────────────────────────────────
header "Phase 2/4: DEVELOPER — Implementing Changes"

DEVELOPER_SYSTEM=$(cat "$DEVELOPER_PROMPT")
LEADER_PLAN=$(cat "$RUN_DIR/01_leader_plan.md")

DEVELOPER_INPUT="$DEVELOPER_SYSTEM

---

## Leader's Plan
$LEADER_PLAN

---

## Original Task
$TASK_CONTENT

---

Follow the Leader's plan and implement the changes. Read existing files before modifying them. Only change what the plan calls for."

claude --print \
    --allowedTools "Read,Edit,Write,Glob,Grep,Bash(git diff:*),Bash(php artisan route:list:*)" \
    -p "$DEVELOPER_INPUT" \
    > "$RUN_DIR/02_developer_changes.md" 2>&1

echo -e "${GREEN}Developer output saved to: $RUN_DIR/02_developer_changes.md${NC}"

# ─────────────────────────────────────────────
# Phase 3: Reviewer (Code Review)
# ─────────────────────────────────────────────
header "Phase 3/4: REVIEWER — Reviewing Changes"

REVIEWER_SYSTEM=$(cat "$REVIEWER_PROMPT")
CURRENT_DIFF=$(cd "$PROJECT_DIR" && git diff HEAD)

REVIEWER_INPUT="$REVIEWER_SYSTEM

---

## Leader's Plan
$LEADER_PLAN

---

## Original Task
$TASK_CONTENT

---

## Current Diff (all uncommitted changes)
\`\`\`diff
$CURRENT_DIFF
\`\`\`

---

Review the diff against the Leader's plan. Read any files you need for full context. Produce your structured review."

echo "$REVIEWER_INPUT" | claude --print \
    --allowedTools "Read,Glob,Grep,Bash(git diff:*),Bash(git log:*)" \
    -p "$REVIEWER_INPUT" \
    > "$RUN_DIR/03_reviewer_report.md" 2>&1

echo -e "${GREEN}Reviewer report saved to: $RUN_DIR/03_reviewer_report.md${NC}"

# ─────────────────────────────────────────────
# Phase 4: QA (Testing & Validation)
# ─────────────────────────────────────────────
header "Phase 4/4: QA — Testing & Validation"

QA_SYSTEM=$(cat "$QA_PROMPT")
REVIEWER_REPORT=$(cat "$RUN_DIR/03_reviewer_report.md")

QA_INPUT="$QA_SYSTEM

---

## Leader's Plan
$LEADER_PLAN

---

## Reviewer's Report
$REVIEWER_REPORT

---

## Original Task
$TASK_CONTENT

---

## Current Diff (all uncommitted changes)
\`\`\`diff
$CURRENT_DIFF
\`\`\`

---

Validate the changes: write tests, trace execution paths, check edge cases, and produce your QA report."

MCP_CONFIG="$PROJECT_DIR/.mcp.json"

claude --print \
    --mcp-config "$MCP_CONFIG" \
    --allowedTools "Read,Write,Glob,Grep,Bash(php artisan test:*),Bash(./vendor/bin/phpunit:*),Bash(./vendor/bin/pest:*),Bash(git diff:*),Bash(composer:*),mcp__postman__*" \
    -p "$QA_INPUT" \
    > "$RUN_DIR/04_qa_report.md" 2>&1

echo -e "${GREEN}QA report saved to: $RUN_DIR/04_qa_report.md${NC}"

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
header "Pipeline Complete"

echo -e "Outputs in: ${BLUE}$RUN_DIR/${NC}"
echo ""
echo -e "  ${CYAN}01_leader_plan.md${NC}       — Architecture & plan"
echo -e "  ${CYAN}02_developer_changes.md${NC} — Implementation log"
echo -e "  ${CYAN}03_reviewer_report.md${NC}   — Code review"
echo -e "  ${CYAN}04_qa_report.md${NC}         — QA testing & validation"
echo ""
echo -e "${YELLOW}Tip: Review 04_qa_report.md for test results and issues.${NC}"
