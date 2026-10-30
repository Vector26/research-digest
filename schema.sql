-- Research Digest tables (n8n Postgres DB)
-- Apply: docker exec -i n8n_postgres psql -U n8n -d n8n < schema.sql

CREATE TABLE IF NOT EXISTS rd_config (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS rd_topics (
  id     SERIAL PRIMARY KEY,
  topic  TEXT NOT NULL UNIQUE,
  weight INT NOT NULL DEFAULT 5,
  active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS rd_feeds (
  id       SERIAL PRIMARY KEY,
  url      TEXT NOT NULL UNIQUE,
  kind     TEXT NOT NULL CHECK (kind IN ('news', 'arxiv', 'hn')),
  category TEXT NOT NULL DEFAULT 'general',
  active   BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS rd_seen (
  url         TEXT PRIMARY KEY,
  title       TEXT,
  source      TEXT,
  mode        TEXT,
  score       INT,
  first_seen  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS rd_seen_sent_at_idx ON rd_seen (sent_at DESC);

-- Config defaults
INSERT INTO rd_config (key, value) VALUES
  ('cron_news', '0 8 * * *'),
  ('cron_papers', '0 8 * * 1'),
  ('relevance_threshold', '6'),
  ('max_items', '8'),
  ('lookback_days', '7'),
  ('model_override', ''),
  ('autoload', 'false'),
  ('ollama_priority', 'qwen3.6:27b,qwen3.6:35b-a3b'),
  ('llama_base_url', 'http://host.docker.internal:8081/v1'),
  ('ollama_base_url', 'http://host.docker.internal:11434'),
  ('notifier_url', 'http://host.docker.internal:8001/notify'),
  ('delivery_mode', 'file'),
  ('ai_backend', 'pi'),
  ('pi_provider', 'llama-hauhaucs'),
  ('pi_model', 'hauhaucs-qwen3.6-35b-iq3m'),
  ('pi_thinking', 'minimal')
ON CONFLICT (key) DO NOTHING;

-- Topics
INSERT INTO rd_topics (topic, weight) VALUES
  ('cybersecurity', 10),
  ('exploits and CVEs', 9),
  ('privacy and surveillance', 7),
  ('AI and large language models', 9),
  ('machine learning research', 8)
ON CONFLICT (topic) DO NOTHING;

-- News feeds
INSERT INTO rd_feeds (url, kind, category) VALUES
  ('https://feeds.feedburner.com/TheHackersNews', 'news', 'cybersecurity'),
  ('https://www.bleepingcomputer.com/feed/', 'news', 'cybersecurity'),
  ('https://krebsonsecurity.com/feed/', 'news', 'cybersecurity'),
  ('https://feeds.arstechnica.com/arstechnica/security', 'news', 'cybersecurity'),
  ('https://www.technologyreview.com/feed/', 'news', 'ai')
ON CONFLICT DO NOTHING;

-- arXiv categories (url holds category code)
INSERT INTO rd_feeds (url, kind, category) VALUES
  ('cs.CR', 'arxiv', 'cybersecurity'),
  ('cs.AI', 'arxiv', 'ai'),
  ('cs.LG', 'arxiv', 'ml'),
  ('cs.CL', 'arxiv', 'nlp')
ON CONFLICT DO NOTHING;
