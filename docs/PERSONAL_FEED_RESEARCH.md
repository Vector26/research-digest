# Personal Algorithm Feed — Research & Architecture

**Status:** Research + multi-source spec (2026-06-26, updated)  
**Goal:** Capy Reader UI + self-hosted personalized feed with transparent trust scoring, ethical preference learning, **multi-format sources** (RSS, Substack, YouTube, …), and **expandable summary cards**.  
**Related:** [research-digest](../) pipeline (this repo); triangulation prompt patterns are described inline below.

---

## Executive summary

**Does this idea exist as one product?** No. Pieces exist; integration is the product.

| Pillar | Closest existing OSS | Gap |
|--------|---------------------|-----|
| Beautiful Android reader | [Capy Reader](https://github.com/jocmp/capyreader) | No built-in like/dislike or algo transparency |
| Personalized ranking | [SignalSieve](https://github.com/sherry255/signalsieve), [Piqued](https://github.com/featurecreep-cron/piqued), [NeuReed](https://github.com/madpin/Neureed) | Rarely combine credibility + explainability |
| Trust / credibility | [CRED-1](https://github.com/aloth/cred-1), [truthcheck](https://github.com/baiyishr/truthcheck) | Domain-level only; no article corroboration out of the box |
| Transparent algo | SignalSieve, [BONSAI paper](https://arxiv.org/html/2509.10776v1) | Research/prototype, not production mobile stack |
| Anti-doom-scroll UX | Miniflux, WeSearch, “No Algo” digests | No learning + trust in one |

**Recommendation:** Build **Fortress Feed** — a self-hosted ranker + Miniflux-compatible API — reuse research-digest ingestion/scoring, CRED-1 + triangulation for trust, SignalSieve-style decomposed ranking, fork Capy for explicit feedback signals, **video cards**, and **collapsible summary rows**.

**Scope update (user request):** Ingestion is **not RSS-only**. **Allowed sources (v1):** Substack (user login), YouTube (user account recs as daily seed), Reddit, Gmail newsletter scan. Substack, YouTube, and other adapters share one normalized `ff_articles` model. YouTube items get Gemini-derived summaries + embeddings; the Capy fork renders a **video card** (thumbnail, duration, tap-to-expand summary, open in YouTube).

---

## System flow — single diagram

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════╗
║                           FORTRESS FEED — END-TO-END FLOW (v1)                                  ║
║                     Allowed sources: Substack · YouTube · Reddit · Gmail                        ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════╝

  ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
  │  YOU (Android) — Capy fork                                                                  │
  │  ┌──────────────┐  login/connect once    ┌─────────────────────────────────────────────┐   │
  │  │ Settings     │ ─────────────────────► │ Link accounts (OAuth / token paste)         │   │
  │  │ • Substack   │                        │  • Substack  → email magic link / session   │   │
  │  │ • YouTube    │                        │  • YouTube   → Google OAuth (read-only)     │   │
  │  │ • Reddit     │                        │  • Reddit    → OAuth (subscribed subs)       │   │
  │  │ • Gmail      │                        │  • Gmail     → OAuth (Newsletters label)     │   │
  │  └──────────────┘                        └──────────────────────┬──────────────────────┘   │
  │                                                                   │                          │
  │  Daily use: ranked feed cards  ◄── Miniflux API ──────────────────┼──────────────────────┤
  │  ┌──────────────────────────────────────────────────────────────┐ │                          │
  │  │ [Trustified ✓]  Source · 3h ago                              │ │                          │
  │  │ Article / video title                                        │ │                          │
  │  │ [▶ thumb 12:34]  ← video only                                │ │                          │
  │  │ ──────────────────────────────────────────────────────────── │ │                          │
  │  │ ▼ 2-line AI summary (tap footer to expand)                   │ │                          │
  │  └──────────────────────────────────────────────────────────────┘ │                          │
  │         │ tap expand          │ 👍 👎  │ "Why this score?"        │                          │
  │         ▼                     ▼         ▼                          │                          │
  │     full summary +      ff_feedback   explain API                  │                          │
  │     key points +        (preference     (transparent               │                          │
  │     timestamps          learning)       weights)                   │                          │
  └────────────────────────────────────────────────────────────────────┼──────────────────────────┘
                                                                       │
                                                                       ▼
╔══════════════════════════════════════════════════════════════════════════════════════════════════╗
║                         FORTRESS FEED SERVER (self-hosted)                                       ║
╠══════════════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                                  ║
║  ┌─────────────────────────────── CONNECTORS (scheduled + on-demand) ───────────────────────┐  ║
║  │                                                                                            │  ║
║  │   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────────────────────┐  │  ║
║  │   │  SUBSTACK   │   │   YOUTUBE   │   │   REDDIT    │   │          GMAIL              │  │  ║
║  │   │  (logged in)│   │  (logged in)│   │  (logged in)│   │       (logged in)           │  │  ║
║  │   ├─────────────┤   ├─────────────┤   ├─────────────┤   ├─────────────────────────────┤  │  ║
║  │   │ • OAuth /   │   │ • Google    │   │ • OAuth     │   │ • Gmail API OAuth           │  │  ║
║  │   │   session   │   │   OAuth     │   │ • subscribed│   │ • scan Labels:              │  │  ║
║  │   │ • private   │   │ • fetch     │   │   subreddits│   │   Newsletters, Promotions   │  │  ║
║  │   │   RSS token │   │   Home feed │   │ • hot/new   │   │   (filter to newsletter   │  │  ║
║  │   │ • paid subs │   │   recs      │   │   per sub   │   │    senders only)            │  │  ║
║  │   │ • /feed +   │   │ • subscribed│   │ • saved     │   │ • extract sender domain +   │  │  ║
║  │   │   full post │   │   channels  │   │   posts opt │   │   List-Unsubscribe header   │  │  ║
║  │   │   HTML      │   │ • **recs as │   │             │   │ • parse HTML body → text    │  │  ║
║  │   │             │   │   daily seed│   │             │   │ • auto-discover new pubs    │  │  ║
║  │   └──────┬──────┘   └──────┬──────┘   └──────┬──────┘   └──────────────┬──────────────┘  │  ║
║  │          │                 │                 │                          │                 │  ║
║  │          └─────────────────┴────────┬────────┴──────────────────────────┘                 │  ║
║  │                                     ▼                                                      │  ║
║  │                        ┌────────────────────────┐                                          │  ║
║  │                        │  NORMALIZE + DEDUPE    │  url / video_id / email Message-Id         │  ║
║  │                        │  → ff_articles         │  content_type: newsletter|video|post     │  ║
║  │                        └───────────┬────────────┘                                          │  ║
║  └────────────────────────────────────┼───────────────────────────────────────────────────────┘  ║
║                                       ▼                                                          ║
║  ┌─────────────────────────────── ENRICH (async queue) ───────────────────────────────────────┐  ║
║  │                                                                                            │  ║
║  │   newsletter / post / substack          youtube video              reddit / gmail         │  ║
║  │          │                                     │                         │                 │  ║
║  │          ▼                                     ▼                         ▼                 │  ║
║  │   ┌─────────────┐                    ┌─────────────────┐         ┌─────────────┐          │  ║
║  │   │ Pi (local)  │                    │ Gemini API      │         │ Pi (local)  │          │  ║
║  │   │ card_summary│                    │ YouTube URL in  │         │ card_summary│          │  ║
║  │   │ full_summary│                    │ → watch + explain│        │ + embed     │          │  ║
║  │   │ + embedding │                    │ key_points[]    │         │             │          │  ║
║  │   └──────┬──────┘                    │ timestamps[]    │         └──────┬──────┘          │  ║
║  │          │                            └────────┬────────┘                │                 │  ║
║  │          └──────────────────┬─────────────────┴─────────────────────────┘                 │  ║
║  │                             ▼                                                              │  ║
║  │                    ff_enrichment (audit: model, time, prompt)                              │  ║
║  └────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                       ▼                                                          ║
║  ┌─────────────────────────────── TRUST (2-step, deterministic) ──────────────────────────────┐  ║
║  │                                                                                            │  ║
║  │   STEP 1: SOURCE TRUST              STEP 2: CORROBORATION                                   │  ║
║  │   ┌─────────────────────┐           ┌──────────────────────────────────────────────┐     │  ║
║  │   │ CRED-1 domain check │           │ Cluster same story across sources (72h)       │     │  ║
║  │   │ user trust/block    │           │ Count independent outlet families             │     │  ║
║  │   │ list                │           │ Tag: [VERIFIED_MULTI] [SINGLE_SOURCE] …       │     │  ║
║  │   └──────────┬──────────┘           └──────────────────────┬───────────────────────┘     │  ║
║  │              └────────────────────┬─────────────────────────┘                             │  ║
║  │                                   ▼                                                        │  ║
║  │                        trustified_score + reasons[]  →  badge on card                       │  ║
║  └────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                       ▼                                                          ║
║  ┌─────────────────────────────── RANK (transparent formula) ────────────────────────────────┐  ║
║  │                                                                                            │  ║
║  │   YOUTUBE SEED LOOP (daily):                                                               │  ║
║  │   ┌──────────────────────────────────────────────────────────────────────────────────┐    │  ║
║  │   │ 1. Pull user's YouTube home recommendations + subscription feed (OAuth)          │    │  ║
║  │   │ 2. Extract topics / channels / titles → interest_seed vector for TODAY           │    │  ║
║  │   │ 3. Boost incoming items that match seed; still apply trust + diversity caps      │    │  ║
║  │   │ 4. Never show raw YT algo order — re-rank with YOUR weights (not engagement)     │    │  ║
║  │   └──────────────────────────────────────────────────────────────────────────────────┘    │  ║
║  │                                                                                            │  ║
║  │   final_score = w_rel×relevance + w_trust×trustified + w_fresh×freshness                  │  ║
║  │                 + w_div×diversity + w_fb×feedback − w_neg×dislikes                         │  ║
║  │                 + w_yt×youtube_seed_match   ← daily recs inform, not dictate             │  ║
║  │                                                                                            │  ║
║  │   + session cap → top N items → "You're caught up"                                         │  ║
║  └────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                       ▼                                                          ║
║  ┌─────────────────────────────── SERVE ─────────────────────────────────────────────────────┐  ║
║  │  Miniflux-compatible API  GET /v1/entries  (card_summary, media, trustified, content_type)│  ║
║  │  PUT read/star/feedback   GET /v1/entries/{id}/explain                                    │  ║
║  └────────────────────────────────────────────────────────────────────────────────────────────┘  ║
║                                       ▼                                                          ║
║                              Postgres (ff_sources, ff_articles, ff_oauth_tokens,               ║
║                                       ff_trust_scores, ff_feedback, ff_youtube_seed_daily)      ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════╝

  LEGEND
  ──────
  • Substack login  → paid posts + private RSS; tokens stored encrypted server-side
  • YouTube login   → home recommendations = daily taste seed; Gemini summarizes picked videos
  • Reddit login    → your subscribed subs only (not global front page)
  • Gmail login     → read-only; newsletters label + sender allowlist; no generic inbox browsing
  • All scores visible on expand — no hidden agenda weights
```

---

## 1. Capy Reader as UI — integration facts

Source: [capyreader](https://github.com/jocmp/capyreader) README, module layout, maintainer blog posts (2026).

### Supported backends

| Backend | API | Capy account type |
|---------|-----|-------------------|
| Local RSS | Direct fetch | `LOCAL` |
| FreshRSS | Google Reader API | `FRESHRSS` |
| Generic GReader host | Google Reader API | `READER` |
| Miniflux | Miniflux REST `/v1/` | `MINIFLUX` |
| Feedbin | Feedbin API v2 | `FEEDBIN` |
| Fever | ❌ Not supported | — |

### Signals Capy syncs today

| Action | Synced? | Notes |
|--------|---------|-------|
| Read / unread | ✅ | All backends |
| Star / unstar | ✅ | All backends |
| Labels (custom) | ✅ | FreshRSS / GReader only |
| Like / dislike | ❌ | **Requires fork** |
| Dismiss / hide topic | ❌ | Local notifications only |

Outbox keys in Capy: `READ`, `STARRED` only ([SyncStatus.kt](https://github.com/jocmp/capyreader/blob/main/capy/src/main/java/com/jocmp/capy/SyncStatus.kt)).

### Best integration path (no Capy fork for MVP)

**Implement a Miniflux-compatible API** (or Google Reader API shim) in front of Fortress Feed.

- User adds account: **Miniflux** → `https://feed.example.com/v1/`
- Capy gets ranked entries via `GET /v1/entries`
- Read/star sync back via `PUT /v1/entries` — Fortress Feed treats these as **preference signals**

**Why Miniflux over GReader:** Cleaner REST, delta sync (`changed_after`), actively supported by Capy since 2026.01.

### Capy fork (Phase 2) — observability

GPL-3.0 allows fork. Touch points:

| Change | File area | Purpose |
|--------|-----------|---------|
| Add `LIKE`, `DISLIKE` to outbox | `SyncStatus.kt` | Explicit feedback |
| Article toolbar buttons | `app` UI | 👍 👎 “Less like this” |
| New delegate methods | `AccountDelegate.kt` | `markLike`, `markDislike`, `hideSource` |
| Miniflux client extension | `minifluxclient` | `POST /v1/entries/{id}/feedback` (custom endpoint) |
| Score breakdown sheet | New composable | “Why this article” transparency panel |
| **Video card composable** | `app` feed list + detail | Thumbnail, duration badge, inline player or YouTube deep-link |
| **Expandable summary row** | Feed list item | Card footer summary; tap expands full AI summary + trust breakdown |

Map star → weak positive until fork ships; labels on FreshRSS can encode `liked` / `disliked` tags as interim hack.

### Feed card UX — expandable bottom summary (required)

Every item in the ranked feed (blog, newsletter, video) uses the same **card shell**:

```
┌─────────────────────────────────────────┐
│ [Trustified ✓]  The Hacker News · 2h    │
│ Title of the article or video           │
│ [optional: 16:9 thumb for video]        │
├─────────────────────────────────────────┤
│ ▼ AI summary (2–3 lines, collapsed)     │  ← tap anywhere on footer to expand
└─────────────────────────────────────────┘
        ↓ expanded
┌─────────────────────────────────────────┐
│ Full card summary (Pi/Gemini generated) │
│ • Key claim 1                           │
│ • Key claim 2                           │
│ [Why this score] [👍] [👎] [Open →]     │
└─────────────────────────────────────────┘
```

**Rules:**

- **Collapsed state:** Always show 2–3 line `card_summary` at card bottom (never title-only doom-scroll tiles).
- **Expand in-place:** Footer tap expands within the list (accordion), not a full navigation — keeps scan flow.
- **Detail view:** “Open →” goes to reader / YouTube / original URL.
- **Video cards:** Same footer pattern; thumbnail + duration overlay above summary; expand reveals Gemini chapter bullets + timestamps.
- **Transparency:** Expanded panel includes trustified badge reasons + score breakdown link.

**API fields** (Miniflux entry extensions via `ff_articles` or custom JSON in `content`):

| Field | Purpose |
|-------|---------|
| `card_summary` | Short text for collapsed footer |
| `full_summary` | Expanded panel text |
| `content_type` | `article` \| `newsletter` \| `video` \| `paper` |
| `media` | `{ thumbnail_url, duration_sec, embed_url }` for video |
| `trustified` | `{ score, tag, reasons[] }` |

Capy’s default list shows title + source only — **fork required** for this card UX even if backend is ready.

---

## 2. Landscape — projects aligned with this vision

### 2.1 Personalized feeds (learning without doom-scroll)

| Project | URL | Reuse |
|---------|-----|-------|
| **SignalSieve** | https://github.com/sherry255/signalsieve | **Architecture template** — decomposed deterministic scores, local feedback, RSS ingest |
| **Piqued** | https://github.com/featurecreep-cron/piqued | FreshRSS → LLM interest profile + thumbs up/down |
| **NeuReed** | https://github.com/madpin/Neureed | pgvector + read/feedback signals |
| **Dibao** | https://github.com/Pls-1q43/Dibao | Embedding sort from like/dislike/save |
| **YourRSS** | https://github.com/XimilalaXiang/YourRSS | FreshRSS extension, Cortex Memory preferences |
| **gmoigneu/signal** | https://github.com/gmoigneu/signal | Daily digest, dedupe, star workflow — overlaps research-digest |
| **semantic-relevance** | https://npmjs.com/package/semantic-relevance | Local embeddings, explainable composite score |

**Pattern to steal:** SignalSieve’s inspectable components (profile match, source quality, freshness, diversity caps, dwell, negative feedback) — not black-box LLM ranking.

### 2.2 Trust / credibility scoring

| Project | URL | Scope | Reuse |
|---------|-----|-------|-------|
| **CRED-1** | https://github.com/aloth/cred-1 | 2,672 low-credibility domains, 0–1 score, on-device JSON, MCP | **Step 1: source trust** |
| **truthcheck** | https://github.com/baiyishr/truthcheck | Claim CLI: publisher + content + corroboration + fact-checkers (25% each) | **Step 2 logic reference** |
| **GDELT Cloud** | https://gdeltcloud.com | Story clusters, multi-outlet evidence | Corroboration API (commercial) |
| **Media Cloud** | https://www.mediacloud.org | 60K+ sources, coverage spread | “Who else covered this?” |
| **CruxNews-OpenNews** | https://github.com/amruth112/CruxNews-OpenNews | Multi-perspective clustering + bias spectrum | UI patterns |
| **News triangulation** | (custom corroboration prompts) | `[VERIFIED_MULTI]`, `[SINGLE_SOURCE]`, etc. | **Step 2: claim corroboration** |

**Important CRED-1 limitation:** Absence from dataset ≠ trustworthy. Only flags *known bad* domains. Neutral unknowns need separate handling.

### 2.3 Transparent / ethical engagement

| Resource | URL | Reuse |
|----------|-----|-------|
| **BONSAI** (paper) | https://arxiv.org/html/2509.10776v1 | Intent-first feeds, procedural transparency |
| **Better Feeds (KGI)** | https://kgi.georgetown.edu/research-and-commentary/fixing-the-feeds-a-policy-roadmap-for-algorithms-that-put-people-first/ | Product requirements: disclosure, user control |
| **Informfully Recommenders** | https://github.com/Informfully/Recommenders | Diversity metrics, user studies |
| **FFC RFC** | https://github.com/iamalnewkirk/ffc-rfc | No algo feeds — useful contrast |
| **WeSearch** | https://wesearch.press | Chronological honesty, count-based trending |

---

## 3. Allowed sources (v1) — login + ingestion

Fortress Feed v1 ingests **only** these four connector families. Each requires **user login once** (OAuth or token) via Capy settings or a small Fortress web connect page.

| Source | Login method | What we pull | Seed / discovery role |
|--------|--------------|--------------|------------------------|
| **Substack** | Substack session / private RSS token from [account/reading](https://substack.com/account/reading) | Paid + free posts from subscriptions | Your subscribed publications |
| **YouTube** | Google OAuth (readonly: subscriptions, recommendations) | Sub feed + **home recommendations** | **Daily seed** — topics/channels from YT recs boost rank for that day |
| **Reddit** | Reddit OAuth | Subscribed subreddits (hot/new) | Communities you chose |
| **Gmail** | Google OAuth (gmail.readonly) | Messages in Newsletters / filtered senders | Auto-discover newsletter URLs + full HTML bodies |

RSS-only public blogs are **out of v1 scope** unless discovered via Gmail (newsletter sender → feed URL if present).

### 3.1 Source adapter details

| Source type | How to ingest | Auth | Full text? | Notes |
|-------------|---------------|------|------------|-------|
| **Substack** | Private `/feed/private/{token}` + subscribed pubs | **User login** | Paid posts with login | Primary newsletter path |
| **YouTube** | Data API: subscriptions + **recommended** + channel uploads | **Google OAuth** | N/A (video) | Recs = daily interest seed; Gemini summarizes |
| **Reddit** | OAuth: `/user/{me}/subreddits` + listing | **Reddit OAuth** | Link + self-text | User subs only |
| **Gmail newsletters** | Gmail API: `label:newsletters` + sender heuristics | **Google OAuth** | Email HTML → text | Discover new pubs from headers |
| ~~RSS / Atom~~ | *(v2)* | — | — | Deferred unless from Gmail discovery |

### 3.2 Substack adapter (logged-in user)

Substack has **no official developer API**. Practical approach:

1. **User connects Substack** in app → Fortress stores encrypted private RSS token + session cookie (if needed).
2. **Public feed fallback:** `https://{publication}.substack.com/feed` for discovery only.
3. **Paid content:** Private RSS URL from [substack.com/account/reading](https://substack.com/account/reading).
3. **Parse:** Atom via existing RSS parser; run **html-to-text** (strip Substack chrome, footers, subscribe CTAs).
4. **Truncated entries:** Optional `--fetch-full-html` pattern (see [rag-starter-kit parse_substack.py](https://github.com/claudian37/rag-starter-kit/blob/main/src/parse_substack.py)).
5. **Normalize:** `content_type: newsletter`, `source_family: substack`, author from `<author>`.

**Pitfalls:** `/rss` returns 404 (use `/feed` only). No per-section feeds. Podcast episodes appear in same feed as `<enclosure>`.

### 3.3 YouTube adapter (logged-in user + daily rec seed)

**Discovery:**

| Method | Auth | Use |
|--------|------|-----|
| YouTube Data API v3 — `activities`, `subscriptions`, **recommended/home** | Google OAuth | Primary v1 path |
| Channel RSS | No login | Fallback for known channel IDs only |

**Daily recommendation seed:**

1. Each morning (or on sync): fetch user's YouTube **home recommendations** + subscription feed.
2. Build `ff_youtube_seed_daily`: `{ topics[], channel_ids[], title_keywords[], embedding_centroid }`.
3. Ranker adds `w_yt × youtube_seed_match` — boosts items aligned with today's taste **without copying YT's order**.
4. Gemini still summarizes each **selected** video for the card footer (not every rec in the seed dump).

**Understanding pipeline (Gemini):**

Public YouTube URLs can be passed directly to Gemini ([video understanding docs](https://ai.google.dev/gemini-api/docs/video-understanding)):

```json
{
  "contents": [{
    "parts": [
      { "text": "Return JSON: { card_summary, full_summary, key_points[], topics[], timestamps[] }" },
      { "file_data": { "file_uri": "https://www.youtube.com/watch?v=VIDEO_ID" } }
    ]
  }]
}
```

**Stored outputs:**

| Field | Use |
|-------|-----|
| `card_summary` | Collapsed card footer (2–3 sentences) |
| `full_summary` | Expanded panel |
| `key_points[]` | Bullet list in expanded view |
| `timestamps[]` | `{ mm:ss, label }` — tap seeks in YouTube app |
| `embedding` | pgvector / local embed of `full_summary` for preference learning |
| `gemini_model` + `processed_at` | Transparency / reproducibility |

**Requirements:**

- `GEMINI_API_KEY` (or Vertex AI with same capability)
- **Public videos only** (private/unlisted fail)
- Free tier: ~8h YouTube/day ([Gemini limits](https://ai.google.dev/gemini-api/docs/video-understanding))
- **1 video per request** on older models; batch ingest with queue + backoff
- Cache by `video_id` — never re-call Gemini unless user requests refresh

**Fallback chain:** Gemini summary → if fail, use RSS description + Pi local summary → if fail, title only.

### 3.4 Reddit adapter (logged-in user)

1. Reddit OAuth — scope: `read`, `mysubreddits`, `history` (optional).
2. Poll **subscribed subreddits** only (`hot` / `new` configurable).
3. Normalize to `content_type: post`; link posts fetch OG metadata; self-posts use body text.
4. No global r/all or algorithmic Reddit home — user-chosen communities only.

### 3.5 Gmail newsletter scanner (logged-in user)

1. Google OAuth — scope: `gmail.readonly` (minimal).
2. Query: `label:newsletters OR category:updates` + sender domain allowlist/blocklist.
3. Parse: `From`, `List-Unsubscribe`, HTML body → clean text; extract Substack/RSS links if present.
4. **Auto-discover:** new senders → prompt user to confirm → add to `ff_sources`.
5. **Privacy:** never index personal mail outside newsletter-like messages; audit log of scanned query.

### 3.6 Recommended extras (v2 — not v1 allowed list)

News & blogs (RSS): THN, Krebs, arXiv, HN Algolia — add when user opts in beyond the four connectors.

### 3.7 Ingest scheduler

```
ff_sources (type, oauth_ref, config, poll_cron)
    → [substack|youtube|reddit|gmail] adapter.fetch()
    → normalize() → ff_articles
    → enrich: Pi (text) / Gemini (video)
    → trust (2-step) → rank (+ youtube_seed_daily) → Miniflux API → Capy
```

---

## 4. Proposed system: Fortress Feed

```
┌─────────────────┐     Miniflux API      ┌──────────────────────────────────────────┐
│  Capy Reader    │ ◄──────────────────► │  Fortress Feed                            │
│  (fork)         │   entries + media    │  ┌─────────────┐  ┌──────────────┐         │
│  • video cards  │   card_summary       │  │ Adapters    │  │ Ranker       │         │
│  • expand summary│  read/star/feedback │  │ RSS Substack│  │ (transparent)│         │
│  • 👍👎         │                      │  │ YouTube HN… │  └──────┬───────┘         │
└─────────────────┘                      │  └──────┬──────┘         │                 │
                                         │         │         ┌──────▼───────┐         │
                                         │  ┌──────▼──────┐  │ Trust (2-step)│         │
                                         │  │ Enrich      │  │ Preference   │         │
                                         │  │ Pi summaries│  └──────────────┘         │
                                         │  │ Gemini video│                            │
                                         │  └─────────────┘                            │
                                         └──────────┬──────────────────────────────────┘
                                                    │
              ┌─────────────┬───────────────────────┼───────────────────────┐
              │             │                       │                       │
        ┌─────▼─────┐ ┌─────▼─────┐          ┌──────▼──────┐         ┌──────▼──────┐
        │ Postgres  │ │ Pi/local  │          │ Gemini API  │         │ CRED-1      │
        │ ff_*      │ │ LLM       │          │ (YouTube)   │         │             │
        └───────────┘ └───────────┘          └─────────────┘         └─────────────┘
```

### Reuse from existing Fortress work

| Existing | Maps to |
|----------|---------|
| `rd_feeds`, `rd_topics` | Subscription + interest profile |
| `pipeline_lib.mjs` fetch/parse | Ingestion |
| Pi curator scoring | Topic relevance (one rank component, not the whole score) |
| Triangulation prompt set | Corroboration worker prompts |
| n8n Postgres | Shared DB or new `ff_*` tables |

---

## 5. Two-step Trustified score (deterministic)

Both steps produce **structured JSON** stored per article. UI shows breakdown; no hidden weights.

### Step 1 — Source trust (deterministic, no LLM)

**Input:** Article URL → registrable domain, author/byline if present, outlet metadata.

**Signals:**

| Signal | Source | Score effect |
|--------|--------|--------------|
| Domain in CRED-1 | Local CRED-1 compact JSON | Penalty 0.0–0.5 by category |
| Domain age / Tranco rank | CRED-1 enrichment or static allowlist | Boost for established tech/security outlets |
| User blocklist | `ff_source_blocks` | Hard exclude |
| User trust list | `ff_source_trust` | Boost (explicit user choice) |
| Paywall / aggregator-only | Heuristic (feed type) | Neutral or slight penalty |

**Output:** `source_trust_score` ∈ [0, 1], `source_trust_reasons[]` (e.g. `"CRED-1: unreliable (0.2)"`, `"user-trusted: krebsonsecurity.com"`).

**Implementation:** Wrap `@aloth/cred1` or embed compact JSON; **no network call** at read time.

### Step 2 — Corroboration trust (deterministic rules + optional LLM assist)

**Input:** Article title + lede + published date.

**Pipeline (rule-first):**

1. **Cluster** — fuzzy title match + entity overlap against items from last 72h across all feeds (reuse research-digest dedupe logic).
2. **Count independent families** — group outlets by parent org / aggregator (Google News RSS ≠ independent from Reuters).
3. **Tag** (from Fortress triangulation):
   - `[VERIFIED_MULTI]` — ≥2 independent non-aggregator families
   - `[SINGLE_SOURCE]` — one family only
   - `[CONTRADICTION]` — conflicting claims detected (keyword/entity mismatch)
   - `[NOT_FOUND]` — no cluster peers
4. **Optional Pi pass** — only for borderline clusters; must output same tags + evidence URLs, never override deterministic tag without evidence.

**Output:** `corroboration_score` ∈ [0, 1], `corroboration_tag`, `peer_articles[]`, `trustified_score = source_trust × corroboration`.

**“Trustified” badge in Capy:** Show when `corroboration_tag = VERIFIED_MULTI` AND `source_trust ≥ 0.7`.

---

## 6. Personal ranking engine (ethical “social media” retention)

### Design principles (non-negotiable)

1. **Every score term visible** — tap article → “Score breakdown”
2. **User owns weights** — sliders for relevance vs trust vs freshness vs diversity
3. **Explicit feedback > implicit** — like/dislike/hide source/topic; dwell is weak signal only
4. **Session bounds** — “You’re caught up” after N items; no infinite scroll default
5. **No engagement optimization** — never optimize for time-on-app; optimize for “useful items read”
6. **Chronological escape hatch** — one tap to pure date order

### Decomposed rank formula (SignalSieve-inspired)

```
final_score =
  w_rel  × relevance      (topics + embedding similarity + Pi topic score)
+ w_trust × trustified    (source_trust × corroboration)
+ w_fresh × freshness     (decay half-life, default 48h)
+ w_div  × diversity      (penalize same source/topic streak)
+ w_fb   × feedback       (explicit like/dislike history)
- w_neg  × negative       (disliked topics/sources/authors)
```

Default weights stored in `ff_user_profile`. User changes logged for transparency.

### Preference learning (good sense, not cunning)

| Signal | Weight | Storage |
|--------|--------|---------|
| 👍 Like | Strong positive | `ff_feedback` |
| 👎 Dislike | Strong negative + downrank similar | `ff_feedback` |
| Star (Capy) | Medium positive | Map from Miniflux bookmark |
| Read to end | Weak positive | Optional; time threshold |
| Quick bounce (<5s) | Weak negative | Optional |
| Hide source | Hard filter | `ff_source_blocks` |
| “More like this” | Boost topic embedding | Explicit action |

**Learning model (Phase 1):** Weighted tag/ topic counts + optional local embedding centroid (semantic-relevance / pgvector).  
**Not Phase 1:** Opaque neural ranker, dwell-only optimization, A/B engagement tests.

### Retention mechanics (ethical)

| Pattern | Implementation |
|---------|----------------|
| Daily “For you” batch | Top 15 ranked; then stop |
| “Trustified picks” lane | Subset with VERIFIED_MULTI |
| Streak of quality | “3 trustified articles today” — informational, not gamified |
| Quiet hours | No push outside window |
| Weekly recap | Optional digest via existing notifier |

---

## 7. What to build vs reuse

### Reuse as-is

- **Capy Reader** — UI (fork for 👍👎 later)
- **Miniflux API contract** — mobile sync surface ([Miniflux API docs](https://miniflux.app/docs/api.html))
- **CRED-1** — source trust Step 1
- **research-digest** — RSS ingest, Pi scoring, Postgres, feed list
- **Fortress triangulation tags** — Step 2 corroboration vocabulary
- **SignalSieve** — ranking component design (read code, don’t fork whole app)

### Adapt / fork

- **Capy Reader** — add feedback UI + transparency sheet + custom Miniflux endpoints
- **Piqued / NeuReed patterns** — feedback loop design only

### Build custom (differentiators)

- Fortress Feed Miniflux-compatible API server
- Two-step trustified scorer with stored evidence
- Transparent score breakdown API (`GET /v1/entries/{id}/explain`)
- User weight profile + audit log
- Story clustering across feeds
- **Source adapters:** Substack, YouTube, HN, Reddit, email-newsletter
- **Gemini YouTube enricher** with cache + queue
- **Capy fork:** video card + expandable summary footer

---

## 8. Data model (sketch)

```sql
-- Sources (multi-type)
ff_sources (
  id, name, type,           -- substack | youtube | reddit | gmail
  url, config JSONB,        -- e.g. { subreddit, channel_id, gmail_query }
  oauth_ref,                -- FK to ff_oauth_tokens (encrypted)
  poll_cron, active, last_fetch
)

ff_oauth_tokens (
  id, provider,              -- substack | google | reddit
  user_id, access_token_enc, refresh_token_enc, expires_at, scopes
)

ff_youtube_seed_daily (
  date, topics JSONB, channel_ids[], embedding, raw_rec_count
)

-- Normalized content
ff_articles (
  id, url UNIQUE, external_id,   -- video_id for YouTube
  source_id, content_type,         -- article | newsletter | video | paper
  title, author, published_at,
  raw_html, clean_text,
  card_summary, full_summary,      -- for expandable card footer
  media JSONB,                     -- { thumbnail_url, duration_sec, embed_url }
  embedding vector(384),           -- optional pgvector
  cluster_id, created_at
)

ff_enrichment (
  article_id, provider,            -- pi | gemini
  model, prompt_version,
  output JSONB, processed_at,
  error TEXT
)

ff_trust_scores   -- source_trust, corroboration, trustified, reasons JSON, computed_at
ff_feedback       -- user_id, article_id, signal (like|dislike|hide_source|hide_topic|expand), at
ff_user_profile   -- weight JSON, quiet_hours, session_cap, intent_text
ff_rank_explain   -- article_id, component scores JSON (for transparency API)
```

**Miniflux entry mapping:** Map `card_summary` → entry `content` snippet; stash `media`, `content_type`, `trustified` in HTML comment or parallel `GET /v1/feed/entries/{id}` extension until Capy fork reads native fields.

Sync Capy read/star → `ff_feedback` + update ranker state on next refresh.

---

## 9. Phased implementation

### Phase 0 — Proof (1–2 weeks)

- [ ] Miniflux API stub: auth, `GET /entries`, `PUT /entries` (read state)
- [ ] RSS + arXiv adapters from `rd_feeds`
- [ ] Pi-generated `card_summary` on ingest
- [ ] Connect Capy to stub URL
- [ ] Document in this file

### Phase 0b — Multi-source + cards (1–2 weeks)

- [ ] `ff_sources` + Substack adapter (public `/feed` + HTML cleanup)
- [ ] YouTube adapter (channel RSS) + Gemini enricher + `ff_enrichment` cache
- [ ] HN Algolia adapter (optional)
- [ ] API returns `card_summary`, `content_type`, `media` on entries

### Phase 1 — Trust (2–3 weeks)

- [ ] CRED-1 integration for Step 1
- [ ] Title clustering + `[VERIFIED_MULTI]` tags for Step 2
- [ ] `GET /entries/{id}/explain` endpoint
- [ ] Postgres tables above

### Phase 2 — Capy fork (2–3 weeks)

- [ ] **Expandable summary card** in feed list (accordion footer)
- [ ] **Video card** composable (thumbnail, duration, expand summary, open YouTube)
- [ ] 👍 👎 + “Why this article” sheet calling explain API
- [ ] Feedback → weight updates (explicit only)
- [ ] Session cap + “caught up” UX in ranked stream

### Phase 3 — Polish

- [ ] Push notifications for trustified picks only
- [ ] OPML + YouTube channel import UI
- [ ] Podcast RSS → Whisper transcript path
- [ ] Media Cloud / GDELT optional corroboration enrichment
- [ ] Email newsletter inbound (Kill the Newsletter / custom alias)

---

## 10. Open questions

1. **FreshRSS vs Miniflux shim?** Miniflux API recommended for Capy native support.
2. **Single user or multi-user?** Fortress is personal — start single-user, API token auth.
3. **LLM in rank loop?** Pi for article/newsletter summaries; **Gemini for YouTube only**; core trust deterministic.
4. **Journalist-level trust?** No mature OSS dataset; defer to outlet-level + user blocklist.
5. **Gemini cost / quota?** Cache aggressively; optional “summarize on Wi‑Fi only” setting.
6. **In-app YouTube playback?** Phase 2: deep-link to YouTube app; optional WebView embed later (ToS consideration).

---

## 11. References

- Capy Reader: https://github.com/jocmp/capyreader
- Capy + Miniflux native API: https://github.com/jocmp/capyreader/discussions/1749
- Miniflux API: https://miniflux.app/docs/api.html
- FreshRSS GReader API: https://freshrss.github.io/FreshRSS/en/developers/06_GoogleReader_API.html
- SignalSieve: https://github.com/sherry255/signalsieve
- CRED-1: https://github.com/aloth/cred-1
- truthcheck: https://github.com/baiyishr/truthcheck
- BONSAI paper: https://arxiv.org/html/2509.10776v1
- Better Feeds policy: https://kgi.georgetown.edu/research-and-commentary/fixing-the-feeds-a-policy-roadmap-for-algorithms-that-put-people-first/
- News triangulation tags: see corroboration section above
- Substack RSS: https://www.wprssaggregator.com/substack-rss-feed/
- Substack ingestion notes: https://aiweekender.substack.com/p/what-i-learned-ingesting-substack
- Gemini video / YouTube URL: https://ai.google.dev/gemini-api/docs/video-understanding
- YouTube channel RSS: `https://www.youtube.com/feeds/videos.xml?channel_id=CHANNEL_ID`
- HN Algolia API: https://hn.algolia.com/api
- semantic-relevance (local embeddings): https://www.npmjs.com/package/semantic-relevance

---

*Next action: Phase 0 + 0b in your feed service repo — Miniflux API stub, RSS/Substack/YouTube adapters, Gemini enricher queue, `card_summary` on all items.*
