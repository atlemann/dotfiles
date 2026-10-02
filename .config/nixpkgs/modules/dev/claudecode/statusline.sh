# Read JSON input from stdin
input=$(cat)

# Extract values using jq
MODEL=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir // ""')
GIT_WORKTREE=$(echo "$input" | jq -r '.workspace.git_worktree // ""')
CTX=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# ---- Colors (ANSI truecolor) ----
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'

ANTHROPIC=$'\033[38;2;217;119;87m'
GREY=$'\033[38;2;150;150;150m'
CYAN=$'\033[38;2;102;192;204m'
GREEN=$'\033[38;2;152;195;121m'
YELLOW=$'\033[38;2;229;192;123m'
RED=$'\033[38;2;224;108;117m'
BLUE=$'\033[38;2;97;175;239m'

pct_color() {
    local v="$1"
    local n=${v%.*}
    [ -z "$n" ] && n=0
    if [ "$n" -ge 80 ]; then printf '%s' "$RED"
    elif [ "$n" -ge 50 ]; then printf '%s' "$YELLOW"
    else printf '%s' "$GREEN"
    fi
}

pct_bar() {
    local value="$1" color="$2"
    local n=${value%.*}
    [ -z "$n" ] && n=0
    local filled=0
    if   [ "$n" -ge 75 ]; then filled=4
    elif [ "$n" -ge 50 ]; then filled=3
    elif [ "$n" -ge 25 ]; then filled=2
    elif [ "$n" -ge 1 ];  then filled=1
    fi
    local glyphs=("▂" "▄" "▆" "█")
    local out="" i
    for i in 0 1 2 3; do
        if [ "$i" -lt "$filled" ]; then
            out+="${color}${glyphs[$i]}${RESET}"
        else
            out+="${DIM}_${RESET}"
        fi
    done
    printf '%s' "$out"
}

fmt_pct() {
    local label="$1" value="$2"
    if [ -n "$value" ]; then
        local color bar
        color=$(pct_color "$value")
        bar=$(pct_bar "$value" "$color")
        printf '%s%s%s %s %s%.0f%%%s' "$color" "$label" "$RESET" "$bar" "$color" "$value" "$RESET"
    else
        printf '%s%s ____ -%s' "$DIM" "$label" "$RESET"
    fi
}

truncate_path() {
    local path="$1" max_length=50
    path="${path/#$HOME/\~}"
    if [ ${#path} -gt $max_length ]; then
        local keep_length=$((max_length - 3))
        local truncated="${path: -$keep_length}"
        if [[ "$truncated" == */* ]]; then
            truncated="${truncated#*/}"
            echo ".../$truncated"
        else
            echo "...$truncated"
        fi
    else
        echo "$path"
    fi
}

get_git_branch() {
    [ -z "$CURRENT_DIR" ] && return
    git -C "$CURRENT_DIR" rev-parse --git-dir >/dev/null 2>&1 || return
    local branch
    branch=$(git -C "$CURRENT_DIR" branch --show-current 2>/dev/null)
    local color="$BLUE" label
    if [ -n "$branch" ]; then
        local porcelain
        porcelain=$(git -C "$CURRENT_DIR" status --porcelain 2>/dev/null)
        if [ -z "$porcelain" ]; then
            color="$GREEN"; label="$branch"
        else
            color="$RED"
            label="$branch ±$(printf '%s\n' "$porcelain" | grep -c .)"
        fi
    else
        branch=$(git -C "$CURRENT_DIR" rev-parse --short HEAD 2>/dev/null)
        [ -z "$branch" ] && return
        label="$branch"
    fi
    printf ' %s[%s]%s' "$color" "$label" "$RESET"
}

SEP="${GREY} | ${RESET}"
TRUNCATED_PATH=$(truncate_path "$CURRENT_DIR")
GIT_BRANCH=$(get_git_branch)
CTX_STR=$(fmt_pct "ctx" "$CTX")

PATH_COLORED="${CYAN}${TRUNCATED_PATH}${RESET}"
MODEL_COLORED="${BOLD}${ANTHROPIC}${MODEL}${RESET}"

WORKTREE_STR=""
if [ -n "$GIT_WORKTREE" ]; then
    WORKTREE_STR=" ${YELLOW}[wt:${GIT_WORKTREE}]${RESET}"
fi

echo -e "${PATH_COLORED}${GIT_BRANCH}${WORKTREE_STR}${SEP}${MODEL_COLORED}${SEP}${CTX_STR}"
