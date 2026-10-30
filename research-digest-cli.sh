#!/usr/bin/env bash
# Menu-driven config for Research News Digest (topics, feeds, schedules, model).
set -euo pipefail

RD_DIR="${RD_DIR:-$(CDPATH= cd -- "$(dirname "$0")" && pwd)}"
N8N_BASE="${N8N_BASE:-http://127.0.0.1:5678}"
NOTIFIER_URL="${NOTIFIER_URL:-http://127.0.0.1:8001/notify}"
WEBHOOK_URL="${WEBHOOK_URL:-$N8N_BASE/webhook/research-digest-run}"

psql_rd() {
  docker exec -i n8n_postgres psql -U n8n -d n8n -Atqc "$1"
}

psql_rd_fmt() {
  docker exec -i n8n_postgres psql -U n8n -d n8n -c "$1"
}

cfg_get() {
  psql_rd "SELECT COALESCE((SELECT value FROM rd_config WHERE key='${1}'), '');"
}

cfg_set() {
  local key="$1" val="$2"
  val="${val//\'/\'\'}"
  psql_rd "INSERT INTO rd_config(key,value) VALUES ('${key}','${val}') ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value;"
}

prompt() {
  local msg="$1" default="${2:-}"
  if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
    whiptail --inputbox "$msg" 10 70 "$default" 3>&1 1>&2 2>&3 || return 1
  else
    read -r -p "$msg [$default]: " ans
    echo "${ans:-$default}"
  fi
}

pause() {
  read -r -p "Press Enter..." _
}

list_topics() {
  echo "=== Topics ==="
  psql_rd_fmt "SELECT id, topic, weight, active FROM rd_topics ORDER BY weight DESC, topic;"
}

add_topic() {
  local topic weight
  topic="$(prompt "Topic text")" || return 0
  weight="$(prompt "Weight 1-10" "5")" || return 0
  topic="${topic//\'/\'\'}"
  psql_rd "INSERT INTO rd_topics(topic,weight,active) VALUES ('${topic}', ${weight:-5}, true) ON CONFLICT(topic) DO UPDATE SET weight=EXCLUDED.weight, active=true;"
  echo "Saved topic: $topic"
}

remove_topic() {
  list_topics
  local id
  id="$(prompt "Topic id to deactivate")" || return 0
  psql_rd "UPDATE rd_topics SET active=false WHERE id=${id};"
  echo "Deactivated topic id $id"
}

list_feeds() {
  echo "=== Feeds ==="
  psql_rd_fmt "SELECT id, kind, category, active, url FROM rd_feeds ORDER BY kind, id;"
}

add_news_feed() {
  local url cat
  url="$(prompt "RSS feed URL")" || return 0
  cat="$(prompt "Category label" "cybersecurity")" || return 0
  url="${url//\'/\'\'}"; cat="${cat//\'/\'\'}"
  psql_rd "INSERT INTO rd_feeds(url,kind,category,active) VALUES ('${url}','news','${cat}',true) ON CONFLICT(url) DO UPDATE SET kind='news', category=EXCLUDED.category, active=true;"
  echo "Saved news feed"
}

remove_feed() {
  list_feeds
  local id
  id="$(prompt "Feed id to deactivate")" || return 0
  psql_rd "UPDATE rd_feeds SET active=false WHERE id=${id};"
  echo "Deactivated feed id $id"
}

list_arxiv() {
  echo "=== arXiv categories ==="
  psql_rd_fmt "SELECT id, url AS category, active FROM rd_feeds WHERE kind='arxiv' ORDER BY id;"
}

add_arxiv_cat() {
  local cat
  cat="$(prompt "arXiv category (e.g. cs.CR)")" || return 0
  cat="${cat//\'/\'\'}"
  psql_rd "INSERT INTO rd_feeds(url,kind,category,active) VALUES ('${cat}','arxiv','${cat}',true) ON CONFLICT(url) DO UPDATE SET kind='arxiv', category=EXCLUDED.category, active=true;"
  echo "Saved arXiv category $cat"
}

remove_arxiv_cat() {
  list_arxiv
  local id
  id="$(prompt "arXiv feed id to deactivate")" || return 0
  psql_rd "UPDATE rd_feeds SET active=false WHERE id=${id};"
}

set_schedule_news() {
  local cron
  cron="$(prompt "News cron (daily)" "$(cfg_get cron_news)")" || return 0
  cfg_set cron_news "$cron"
  echo "Saved cron_news=$cron (re-run: rdigest deploy to sync n8n schedule)"
}

set_schedule_papers() {
  local cron
  cron="$(prompt "Papers cron (weekly)" "$(cfg_get cron_papers)")" || return 0
  cfg_set cron_papers "$cron"
  echo "Saved cron_papers=$cron (re-run: rdigest deploy to sync n8n schedule)"
}

set_threshold() {
  local t m
  t="$(prompt "Relevance threshold 1-10" "$(cfg_get relevance_threshold)")" || return 0
  m="$(prompt "Max items per digest" "$(cfg_get max_items)")" || return 0
  cfg_set relevance_threshold "$t"
  cfg_set max_items "$m"
  echo "Saved threshold=$t max_items=$m"
}

set_model_override() {
  local cur; cur="$(cfg_get model_override)"
  echo "Current override: ${cur:-<auto detect GPU model>}"
  echo "Examples: llama | ollama:qwen3.6:27b | http://host.docker.internal:8081/v1"
  local val
  val="$(prompt "Model override (blank = auto)" "$cur")" || return 0
  cfg_set model_override "$val"
  echo "Saved model_override"
}

toggle_autoload() {
  local cur; cur="$(cfg_get autoload)"
  if [ "$cur" = "true" ]; then
    cfg_set autoload "false"
    echo "autoload=false"
  else
    cfg_set autoload "true"
    echo "autoload=true (will warm Ollama if no GPU model is reachable)"
  fi
}

run_now() {
  local mode="${1:-news}"
  echo "Triggering $mode digest via webhook..."
  curl -sfS -X POST "${WEBHOOK_URL}?mode=${mode}" -H 'Content-Type: application/json' -d '{}' \
    && echo "Triggered." || echo "Trigger failed (is workflow active?)"
}

test_notify() {
  curl -sfS -X POST "$NOTIFIER_URL" \
    -H 'Content-Type: application/json' \
    -d '{"message":"Research digest CLI test OK","source":"rdigest"}' \
    && echo "Test message sent." || echo "Notifier failed."
}

show_history() {
  echo "=== Recent sent items ==="
  psql_rd_fmt "SELECT sent_at, mode, score, left(title,80) AS title, left(url,90) AS url FROM rd_seen WHERE sent_at IS NOT NULL ORDER BY sent_at DESC LIMIT 15;"
}

deploy_workflow() {
  if [ -f "$RD_DIR/install.sh" ]; then
    bash "$RD_DIR/install.sh" --push-only
  else
    echo "install.sh not found at $RD_DIR"
    return 1
  fi
}

show_status() {
  echo "News cron:    $(cfg_get cron_news)"
  echo "Papers cron:  $(cfg_get cron_papers)"
  echo "Threshold:    $(cfg_get relevance_threshold) | max items: $(cfg_get max_items)"
  echo "Model override: $(cfg_get model_override)"
  echo "Autoload:     $(cfg_get autoload)"
  echo "Webhook:      $WEBHOOK_URL"
}

menu_whiptail() {
  while true; do
    choice=$(whiptail --title "Research Digest" --menu "Configure topics, feeds, and runs" 22 78 14 \
      "1" "List topics" \
      "2" "Add topic" \
      "3" "Remove topic" \
      "4" "List news feeds" \
      "5" "Add news feed" \
      "6" "Remove feed" \
      "7" "List arXiv categories" \
      "8" "Add arXiv category" \
      "9" "Remove arXiv category" \
      "a" "Set news schedule (cron)" \
      "b" "Set papers schedule (cron)" \
      "c" "Set threshold & max items" \
      "d" "Set/clear model override" \
      "e" "Toggle Ollama autoload" \
      "f" "Run news digest now" \
      "g" "Run papers digest now" \
      "h" "Send test Telegram" \
      "i" "Show recent history" \
      "j" "Show status" \
      "k" "Deploy workflow to n8n" \
      "q" "Quit" 3>&1 1>&2 2>&3) || exit 0
    case "$choice" in
      1) list_topics; pause ;;
      2) add_topic; pause ;;
      3) remove_topic; pause ;;
      4) list_feeds; pause ;;
      5) add_news_feed; pause ;;
      6) remove_feed; pause ;;
      7) list_arxiv; pause ;;
      8) add_arxiv_cat; pause ;;
      9) remove_arxiv_cat; pause ;;
      a) set_schedule_news; pause ;;
      b) set_schedule_papers; pause ;;
      c) set_threshold; pause ;;
      d) set_model_override; pause ;;
      e) toggle_autoload; pause ;;
      f) run_now news; pause ;;
      g) run_now papers; pause ;;
      h) test_notify; pause ;;
      i) show_history; pause ;;
      j) show_status; pause ;;
      k) deploy_workflow; pause ;;
      q) exit 0 ;;
    esac
  done
}

menu_select() {
  PS3="Choose: "
  local opts=(
    "List topics"
    "Add topic"
    "Remove topic"
    "List news feeds"
    "Add news feed"
    "Remove feed"
    "List arXiv categories"
    "Add arXiv category"
    "Remove arXiv category"
    "Set news schedule"
    "Set papers schedule"
    "Set threshold & max items"
    "Set model override"
    "Toggle autoload"
    "Run news now"
    "Run papers now"
    "Test Telegram"
    "Show history"
    "Show status"
    "Deploy workflow"
    "Quit"
  )
  while true; do
    select _ in "${opts[@]}"; do
      case "$REPLY" in
        1) list_topics ;;
        2) add_topic ;;
        3) remove_topic ;;
        4) list_feeds ;;
        5) add_news_feed ;;
        6) remove_feed ;;
        7) list_arxiv ;;
        8) add_arxiv_cat ;;
        9) remove_arxiv_cat ;;
        10) set_schedule_news ;;
        11) set_schedule_papers ;;
        12) set_threshold ;;
        13) set_model_override ;;
        14) toggle_autoload ;;
        15) run_now news ;;
        16) run_now papers ;;
        17) test_notify ;;
        18) show_history ;;
        19) show_status ;;
        20) deploy_workflow ;;
        21) exit 0 ;;
        *) echo "Invalid" ;;
      esac
      break
    done
  done
}

main() {
  if ! docker ps --format '{{.Names}}' | grep -qx 'n8n_postgres'; then
    echo "n8n_postgres container not running." >&2
    exit 1
  fi
  case "${1:-}" in
    run-news) run_now news ;;
    run-papers) run_now papers ;;
    status) show_status ;;
    deploy) deploy_workflow ;;
    "")
      if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
        menu_whiptail
      else
        menu_select
      fi
      ;;
    *) echo "Usage: rdigest [run-news|run-papers|status|deploy]" >&2; exit 2 ;;
  esac
}

main "$@"
