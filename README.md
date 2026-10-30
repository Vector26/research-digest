# Research Digest

Automated **news**, **arXiv**, and **Hacker News** digest pipeline: fetch RSS/arXiv feeds, dedupe against recent sends, score items with a local LLM ([Pi coding agent](https://github.com/mariozechner/pi-coding-agent)), rank by relevance to your topics, and write `latest.json` / `latest.txt` (optional HTTP notifier).

Designed to run on a schedule or on demand via **n8n**, with configuration stored in Postgres.

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

1. **n8n** loads `rd_config`, `rd_topics`, `rd_feeds`, and recent `rd_seen` rows, writes `.run-input.json` under the runtime directory, and executes `run_digest.sh`.
2. **`pipeline_lib.mjs`** fetches feeds, dedupes, calls Pi with `pi/agent/curator_system.md`, ranks by score and topic weights.
3. Results are persisted to `rd_seen` and optional notification endpoints.

## Requirements

- Docker with an **n8n** stack and **Postgres** (workflow uses container name `n8n_postgres` by default).
- **Node.js** 18+ inside the n8n runtime (or on the host for local runs).
- **Pi coding agent** with a local OpenAI-compatible LLM (defaults assume `host.docker.internal:8081`).
- Environment file for n8n API access: `N8N_API_KEY`, `POSTGRES_PASSWORD` (see `install.sh`).

## Install

```bash
git clone https://github.com/Vector26/research-digest.git
cd research-digest

# Point at your n8n .env (override if needed)
export N8N_ENV="$HOME/n8n/.env"
export N8N_FILES_DIR="$HOME/n8n/n8n_files"   # optional

./install.sh
```

`install.sh` applies `schema.sql`, copies pipeline files into `$N8N_FILES_DIR/research-digest`, pushes the n8n workflow from `research_digest.import.json`, and optionally adds an `rdigest` alias to your shell rc.

Use `./install.sh --push-only` to redeploy the workflow without re-applying schema.

## CLI (`research-digest-cli.sh`)

Interactive menu (whiptail when available):

| Action | Purpose |
|--------|---------|
| Topics | Add/remove weighted interest topics for scoring |
| Feeds | Manage RSS, arXiv category codes, HN |
| Schedules | Cron strings for news vs papers (sync via deploy) |
| Model | Pi provider/model/thinking level |
| Run now | POST to n8n webhook |
| Deploy | Re-run workflow push to n8n |
| Verify | Run `verify_scopes.sh` integration checks |

```bash
./research-digest-cli.sh
# or after install: rdigest
```

## Database schema

Tables (see `schema.sql`):

| Table | Role |
|-------|------|
| `rd_config` | Key/value settings (thresholds, cron, model, notifier URL) |
| `rd_topics` | Interest topics with weights |
| `rd_feeds` | Feed URLs or arXiv categories (`kind`: `news`, `arxiv`, `hn`) |
| `rd_seen` | URLs already sent (dedupe + audit) |

Apply manually:

```bash
docker exec -i n8n_postgres psql -U n8n -d n8n < schema.sql
```

## n8n integration

- Import template: `research_digest.import.json` (placeholder credential id `__RD_PG_CRED_ID__`; `push_research_digest_to_n8n.sh` creates/updates Postgres credentials and activates the workflow).
- **Triggers:** daily news cron, weekly papers cron, POST webhook `research-digest-run?mode=news|papers`, manual trigger.
- **Runtime path:** mount n8n files so `/files/research-digest` matches your `N8N_FILES_DIR/research-digest` copy.

Set `N8N_BASE` (default `http://127.0.0.1:5678`) when pushing from a non-default host.

## Local / host run

```bash
export RD_OUT_DIR=/tmp/research-digest
export RD_INPUT=/tmp/research-digest/.run-input.json
# write .run-input.json with { "mode": "news", "payload": { ... } }
./run_digest.sh
```

Pi agent config lives under `pi/agent/` (`models.json` for Docker, `models.host.json` for host-side llama on `127.0.0.1`). Copy `pi/agent/auth.json.example` to `auth.json` if your Pi setup requires it (gitignored).

## Verification

```bash
./verify_scopes.sh news   # or papers
```

Checks schema, feed fetch, optional Pi/llama health, n8n webhook execution, and output files.

## Docs

- `docs/PERSONAL_FEED_RESEARCH.md` — longer-form notes on personalized feed research (separate from the core digest pipeline).

## License

MIT — see [LICENSE](LICENSE).
