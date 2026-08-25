#!/usr/bin/env bash

# Load only the client-safe Supabase settings from the project-local env file.
# The env file is sourced in a subshell so unrelated/server-only variables do
# not leak into Flutter build or run processes.
load_supabase_client_env() {
  local root_dir="$1"
  local env_file="${root_dir}/.env.local"
  local separator=$'\034'
  local loaded=""
  local file_url=""
  local file_key=""

  if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_ANON_KEY:-}" ]]; then
    return 0
  fi

  if [[ -f "$env_file" ]]; then
    loaded="$(
      unset SUPABASE_URL SUPABASE_BASE_URL SUPABASE_ANON_KEY
      # shellcheck disable=SC1090
      source "$env_file" >/dev/null
      printf '%s%s%s' \
        "${SUPABASE_URL:-${SUPABASE_BASE_URL:-}}" \
        "$separator" \
        "${SUPABASE_ANON_KEY:-}"
    )"
    file_url="${loaded%%"$separator"*}"
    file_key="${loaded#*"$separator"}"

    if [[ -z "${SUPABASE_URL:-}" ]]; then
      SUPABASE_URL="$file_url"
    fi
    if [[ -z "${SUPABASE_ANON_KEY:-}" ]]; then
      SUPABASE_ANON_KEY="$file_key"
    fi
  fi
}

require_supabase_client_env() {
  local root_dir="$1"
  local env_file="${root_dir}/.env.local"

  if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
    echo "Missing SUPABASE_URL/SUPABASE_ANON_KEY." >&2
    echo "Set them in the environment or add client-only values to ${env_file}." >&2
    return 1
  fi

  if [[ ! "$SUPABASE_URL" =~ ^https?:// ]]; then
    echo "Invalid SUPABASE_URL: expected an http:// or https:// URL." >&2
    return 1
  fi

  if [[ "$SUPABASE_ANON_KEY" == sb_secret_* ]]; then
    echo "Refusing a server-side Supabase secret; use a publishable/anon client key." >&2
    return 1
  fi
}
