<div align="center">

# Research Digest

**Your interests, scored by a local LLM — news, arXiv, and HN in one ranked digest.**

[![Node.js](https://img.shields.io/badge/Node.js-18+-339933?style=flat-square&logo=nodedotjs&logoColor=white)](https://nodejs.org/)
[![n8n](https://img.shields.io/badge/Orchestration-n8n-EA4B71?style=flat-square&logo=n8n&logoColor=white)](https://n8n.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Docker_%7C_Linux-lightgrey?style=flat-square)](install.sh)

</div>

---

## Why it exists

Feeds multiply faster than attention. **Research Digest** pulls RSS, arXiv categories, and Hacker News, **dedupes** against what you already sent, **scores** each item with a local LLM ([Pi coding agent](https://github.com/mariozechner/pi-coding-agent)) against weighted topics, and writes **`latest.json` / `latest.txt`** — with optional webhook notification. Configuration lives in **Postgres**; schedules and manual runs flow through **n8n**.

## Features

| | |
|---|---|
| **Multi-source ingest** | RSS, arXiv category codes, HN |
| **LLM curation** | Pi agent + `pi/agent/curator_system.md` for score and summary |
| **Topic weights** | Rank by relevance to your interests |
| **Dedupe & audit** | `rd_seen` tracks URLs already delivered |
| **n8n-native** | Cron, webhooks, and deployable workflow JSON |
| **CLI menu** | `research-digest-cli.sh` / `rdigest` for topics, feeds, schedules, run-now |

## Architecture

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────────────┐
│ n8n triggers    │────▶│ Load config  │────▶│ run_digest.sh       │
│ (cron/webhook)  │     │ from Postgres│     │ → run_digest.mjs    │
└─────────────────┘     └──────────────┘     └──────────┬──────────┘
                                                        │
                        ┌───────────────────────────────┼───────────────────────────────┐
                        ▼                               ▼                               ▼
                 fetch RSS/arXiv/HN              Pi LLM score + summary            rank + format digest
                        │                               │                               │
                        └───────────────────────────────┴───────────────────────────────┘
                                                        │
                        ┌───────────────────────────────┴───────────────────────────────┐
                        ▼                                                               ▼
                 Record seen URLs in Postgres                              latest.json / notify webhook
```

1. **n8n** loads `rd_config`, `rd_topics`, `rd_feeds`, recent `rd_seen`, writes `.run-input.json`, runs `run_digest.sh`.
2. **`pipeline_lib.mjs`** fetches, dedupes, calls Pi, ranks by score and topic weights.
3. Results persist to `rd_seen` and optional notifier endpoints.

## Quick start

**Requirements:** Docker **n8n** + **Postgres** (default container `n8n_postgres`), Node 18+ in the n8n runtime, Pi agent + local OpenAI-compatible LLM (defaults often `host.docker.internal:8081`), `N8N_API_KEY` and `POSTGRES_PASSWORD` in your n8n env.

```bash
git clone https://github.com/Vector26/research-digest.git
cd research-digest

export N8N_ENV="$HOME/n8n/.env"
export N8N_FILES_DIR="$HOME/n8n/n8n_files"   # optional

./install.sh
```

`install.sh` applies `schema.sql`, copies pipeline files to `$N8N_FILES_DIR/research-digest`, pushes workflow from `research_digest.import.json`, optionally adds `rdigest` alias.

Redeploy workflow only: `./install.sh --push-only`

```bash
./research-digest-cli.sh
./verify_scopes.sh news   # or papers
```

Set `N8N_BASE` (default `http://127.0.0.1:5678`) when pushing from a non-default host.

### Database

| Table | Role |
|-------|------|
| `rd_config` | Thresholds, cron, model, notifier URL |
| `rd_topics` | Interest topics with weights |
| `rd_feeds` | URLs or arXiv categories (`news`, `arxiv`, `hn`) |
| `rd_seen` | Dedupe + audit |

Manual apply:

```bash
docker exec -i n8n_postgres psql -U n8n -d n8n < schema.sql
```

### Local / host run

```bash
export RD_OUT_DIR=/tmp/research-digest
export RD_INPUT=/tmp/research-digest/.run-input.json
# write .run-input.json with { "mode": "news", "payload": { ... } }
./run_digest.sh
```

Pi config: `pi/agent/` (`models.json` for Docker, `models.host.json` for host llama on `127.0.0.1`). Copy `pi/agent/auth.json.example` → `auth.json` if required (gitignored).

**n8n triggers:** daily news cron, weekly papers cron, POST `research-digest-run?mode=news|papers`, manual trigger. Mount n8n files so `/files/research-digest` matches your `N8N_FILES_DIR/research-digest` copy.

> **What makes it different**
>
> Not another “RSS to email” script — **your topics drive ranking**, a **local model** does the reading, and **Postgres + n8n** make schedules and dedupe auditable instead of buried in cron comments.

## Status

| Area | State |
|------|--------|
| Pipeline + schema | Stable for scheduled runs |
| n8n workflow | Imported via `push_research_digest_to_n8n.sh` |
| Pi / LLM endpoint | You configure provider and models |
| Extra research notes | [docs/PERSONAL_FEED_RESEARCH.md](./docs/PERSONAL_FEED_RESEARCH.md) |

---

<div align="center">

**MIT** — see [LICENSE](LICENSE)

Built by **[Vector26](https://github.com/Vector26)** · Personalized digests, self-hosted

</div>
