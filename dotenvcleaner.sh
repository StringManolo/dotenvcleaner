#!/usr/bin/env bash

split() {
  local var_name="$1"
  local separator="$2"
  local -n ref="$var_name"
  local target="$ref"
  ref=()

  if [[ -z "$separator" ]]; then
    local len=${#target}
    for ((i=0; i<len; i++)); do
      ref+=("${target:i:1}")
    done
    return 0
  fi

  local temp="$target"
  local part=""

  while [[ -n "$temp" ]]; do
    if [[ "$temp" == *"$separator"* ]]; then
      part="${temp%%"$separator"*}"
      ref+=("$part")
      temp="${temp#*"$separator"}"
    else
      ref+=("$temp")
      break
    fi
  done

  if [[ -z "$target" ]] || [[ "$target" == *"$separator" ]]; then
    ref+=("")
  fi
}

join() {
  local var_name="$1"
  local separator="$2"
  local -n ref="$var_name"
  local elements=("${ref[@]}")
  ref=""

  if [[ ${#elements[@]} -eq 0 ]]; then
    return 0
  fi

  ref="${elements[0]}"
  for ((i=1; i<${#elements[@]}; i++)); do
    ref+="${separator}${elements[i]}"
  done
}

readFile() {
  local file_path="$1"
  local var_name="$2"
  local -n ref="$var_name"

  if [[ -z "$file_path" ]]; then
    echo "Error: Filepath not provided" >&2
    return 1
  fi

  if [[ ! -f "$file_path" ]]; then
    echo "Error: file '$file_path' not found" >&2
    return 1
  fi

  if [[ ! -r "$file_path" ]]; then
    echo "Error: Permission denied reading '$file_path'" >&2
    return 1
  fi

  ref="$(< "$file_path")"
  return 0
}

clean_env() {
  local env_file="$1"
  local envFile=""

  if ! readFile "$env_file" "envFile"; then
    return 1
  fi

  split envFile $'\n'

  for line in "${envFile[@]}"; do
    if [[ -z "$line" || "$line" == \#* ]]; then
      echo "$line"
      continue
    fi

    split line "="

    if [[ ${#line[@]} -gt 1 ]]; then
      echo "${line[0]}="
    else
      echo "${line[0]}"
    fi
  done
}

install_hook() {
  local hook_dir=".git/hooks"
  local hook_file="$hook_dir/pre-commit"

  if [[ ! -d ".git" ]]; then
    echo "Error: Not in a git repository root" >&2
    exit 1
  fi

  mkdir -p "$hook_dir"

  cat > "$hook_file" << 'HOOK_EOF'
#!/usr/bin/env bash

ENV_FILE=".env"
BACKUP_FILE=".env.backup.$"

restore_env() {
  if [[ -f "$BACKUP_FILE" ]]; then
    mv "$BACKUP_FILE" "$ENV_FILE"
    echo "✓ .env restored"
  fi
}

trap restore_env EXIT

if [[ ! -f "$ENV_FILE" ]]; then
  exit 0
fi

if ! git diff --cached --name-only | grep -q "^\.env$"; then
  exit 0
fi

echo "⚠️  WARNING: .env detected in staged files"
echo ""

cp "$ENV_FILE" "$BACKUP_FILE"

if [[ -f "./dotenvcleaner.sh" ]]; then
  ./dotenvcleaner.sh "$ENV_FILE" > "$ENV_FILE.tmp"
  mv "$ENV_FILE.tmp" "$ENV_FILE"
else
  echo "Error: dotenvcleaner.sh not found" >&2
  exit 1
fi

echo "============================================"
echo "CLEANED .env CONTENT TO BE COMMITTED:"
echo "============================================"
cat "$ENV_FILE"
echo "============================================"
echo ""

read -p "Are the tokens clean? (y/N): " -n 1 -r </dev/tty
echo

if [[ ! $REPLY =~ ^[YySs]$ ]]; then
  echo "Commit cancelled by user"
  exit 1
fi

git add "$ENV_FILE"

echo "✓ Commit authorized with cleaned .env"
HOOK_EOF

  chmod +x "$hook_file"

  echo "✅ Hook installed at $hook_file"
}

if [[ "$1" == "install" ]]; then
  install_hook
elif [[ -n "$1" ]]; then
  clean_env "$1"
else
  echo "Usage:"
  echo "  $0 install          - Install git hook"
  echo "  $0 <file>           - Clean an .env file"
  exit 1
fi
