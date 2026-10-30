/** Shared research-digest pipeline logic (used by run_digest.mjs and verify_scopes.sh). */

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

export function decodeXml(s) {
  return String(s || '')
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .trim();
}

export function pickTag(block, tag) {
  const re = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'i');
  const m = String(block || '').match(re);
  return m ? decodeXml(m[1]) : '';
}

export function parseRss(xml, source, maxItems = 8) {
  const items = [];
  const re = /<item[\s\S]*?<\/item>/gi;
  let m;
  while ((m = re.exec(xml))) {
    const block = m[0];
    const title = pickTag(block, 'title');
    let url = pickTag(block, 'link');
    if (!url) {
      const guid = pickTag(block, 'guid');
      if (/^https?:\/\//i.test(guid)) url = guid;
    }
    const summary = pickTag(block, 'description') || pickTag(block, 'content:encoded') || '';
    const published = pickTag(block, 'pubDate') || pickTag(block, 'updated') || '';
    if (title && url) {
      items.push({ title, url, source, published, summary: summary.slice(0, 1200) });
    }
    if (items.length >= maxItems) break;
  }
  return items;
}

export function parseArxiv(xml, category, maxItems = 8) {
  const items = [];
  const re = /<entry[\s\S]*?<\/entry>/gi;
  let m;
  while ((m = re.exec(xml))) {
    const block = m[0];
    const title = pickTag(block, 'title').replace(/\s+/g, ' ');
    const summary = pickTag(block, 'summary').replace(/\s+/g, ' ');
    const published = pickTag(block, 'published') || pickTag(block, 'updated') || '';
    const id = pickTag(block, 'id');
    let url = id;
    const pdfMatch = block.match(/<link[^>]*title="pdf"[^>]*href="([^"]+)"/i);
    if (pdfMatch) url = pdfMatch[1];
    if (title && url) {
      items.push({
        title,
        url,
        source: `arXiv:${category}`,
        published,
        summary: summary.slice(0, 1200),
      });
    }
    if (items.length >= maxItems) break;
  }
  return items;
}

export async function httpText(url, timeoutMs = 20000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: ctrl.signal });
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
    return await res.text();
  } finally {
    clearTimeout(t);
  }
}

export async function httpJson(method, url, body, timeoutMs = 20000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      method,
      headers: body !== undefined ? { 'Content-Type': 'application/json' } : undefined,
      body: body !== undefined ? JSON.stringify(body) : undefined,
      signal: ctrl.signal,
    });
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
    return await res.json();
  } finally {
    clearTimeout(t);
  }
}

/** Pi CLI backend — uses bundled curator prompt + HauhauCS provider. */
export function resolvePi(config = {}) {
  return {
    provider: 'pi',
    backend: 'pi',
    pi_provider: config.pi_provider || 'llama-hauhaucs',
    pi_model: config.pi_model || 'hauhaucs-qwen3.6-35b-iq3m',
    pi_thinking: config.pi_thinking || 'minimal',
    model: config.pi_model || 'hauhaucs-qwen3.6-35b-iq3m',
    ai_ok: true,
  };
}

function piInvoke(config) {
  const cli = '/host-node/lib/node_modules/@mariozechner/pi-coding-agent/dist/cli.js';
  if (fs.existsSync(cli)) {
    return { bin: process.execPath, prefix: [cli] };
  }
  if (config.pi_bin) return { bin: config.pi_bin, prefix: [] };
  if (fs.existsSync('/host-node/bin/pi')) return { bin: '/host-node/bin/node', prefix: [cli] };
  return { bin: 'pi', prefix: [] };
}

function piAgentDir(config) {
  const nested = path.join(process.env.HOME || '', '.pi', 'agent');
  if (fs.existsSync(path.join(nested, 'curator_system.md'))) return nested;
  return config.pi_agent_dir || process.env.PI_AGENT_DIR || '/files/research-digest/pi/agent';
}

export function scoreWithPi(items, topics, config = {}) {
  const agentDir = piAgentDir(config);
  const systemPath = path.join(agentDir, 'curator_system.md');
  const systemPrompt = fs.readFileSync(systemPath, 'utf8');
  const topicLine = topics.map((t) => t.topic).join(', ');
  const payload = {
    topics: topicLine,
    items: items.map((it, index) => ({
      index,
      title: it.title,
      source: it.source,
      excerpt: String(it.summary || '').slice(0, 400),
    })),
  };
  const userPrompt = `Score and summarize each item below for the topic list.
Return ONLY a JSON array: [{"index":0,"score":8,"summary":"..."}]

${JSON.stringify(payload, null, 2)}`;

  const piArgs = [
    '--provider', config.pi_provider || 'llama-hauhaucs',
    '--model', config.pi_model || 'hauhaucs-qwen3.6-35b-iq3m',
    '--no-session',
    '--no-tools',
    '--thinking', config.pi_thinking || 'minimal',
    '--mode', 'text',
    '--system-prompt', systemPrompt,
    '-p', userPrompt,
  ];
  const { bin, prefix } = piInvoke(config);
  const args = [...prefix, ...piArgs];

  const env = { ...process.env };
  if (process.env.PI_HOME) env.HOME = process.env.PI_HOME;

  const run = spawnSync(bin, args, {
    encoding: 'utf8',
    timeout: Number(config.pi_timeout_ms || 240000),
    env,
    maxBuffer: 8 * 1024 * 1024,
  });

  const stdout = String(run.stdout || '').trim();
  const stderr = String(run.stderr || '').trim();
  if (run.error) {
    throw new Error(`pi spawn failed: ${run.error.message}`);
  }
  if (run.status !== 0 && !stdout) {
    throw new Error(`pi exit ${run.status}: ${stderr.slice(0, 500)}`);
  }

  const parsed = extractJsonArray(stdout) || [];
  for (const row of parsed) {
    const idx = Number(row.index);
    if (!Number.isFinite(idx) || !items[idx]) continue;
    items[idx].score = Math.max(1, Math.min(10, Number(row.score) || 5));
    items[idx].ai_summary = String(row.summary || '').slice(0, 400);
  }
  for (const it of items) {
    if (!it.ai_summary) it.ai_summary = String(it.summary || '').slice(0, 200);
    if (!it.score) it.score = 5;
  }

  return { raw: stdout, parsed, stderr: stderr.slice(0, 500) };
}

/** @deprecated raw HTTP — use scoreWithPi instead */
export async function resolveModel(config) {
  return resolvePi(config);
}

export function extractJsonArray(text) {
  const raw = String(text || '').trim();
  const start = raw.indexOf('[');
  const end = raw.lastIndexOf(']');
  if (start >= 0 && end > start) {
    try {
      return JSON.parse(raw.slice(start, end + 1));
    } catch (_) {}
  }
  const objStart = raw.indexOf('{');
  const objEnd = raw.lastIndexOf('}');
  if (objStart >= 0 && objEnd > objStart) {
    try {
      return [JSON.parse(raw.slice(objStart, objEnd + 1))];
    } catch (_) {}
  }
  return null;
}

function messageText(message) {
  const content = String(message?.content || '');
  const reasoning = String(message?.reasoning_content || '');
  const merged = [content, reasoning].filter(Boolean).join('\n');
  return merged.replace(/<think>[\s\S]*?<\/redacted_thinking>/gi, '').trim();
}

export async function scoreBatch(items, topics, modelInfo) {
  return scoreWithPi(items, topics, modelInfo);
}

export function dedupeItems(collected, seenUrls, maxItems = 16) {
  const seen = new Set(seenUrls || []);
  const out = [];
  const local = new Set();
  for (const it of collected) {
    const url = String(it.url || '').trim();
    if (!url || local.has(url) || seen.has(url)) continue;
    local.add(url);
    out.push({ ...it, url });
    if (out.length >= maxItems) break;
  }
  return out;
}

export async function fetchItems(mode, feeds, perFeed = 6) {
  const active = feeds.filter((f) => {
    if (mode === 'papers') return f.kind === 'arxiv';
    return f.kind === 'news' || f.kind === 'hn';
  });
  const collected = [];
  const feedStats = [];
  for (const feed of active) {
    try {
      let batch = [];
      if (feed.kind === 'arxiv') {
        const cat = String(feed.url || '').trim();
        const q =
          'http://export.arxiv.org/api/query?search_query=' +
          encodeURIComponent(`cat:${cat}`) +
          '&sortBy=submittedDate&sortOrder=descending&max_results=' +
          perFeed;
        const xml = await httpText(q, 30000);
        batch = parseArxiv(xml, cat, perFeed);
      } else {
        const xml = await httpText(feed.url, 30000);
        batch = parseRss(xml, feed.category || feed.url, perFeed);
      }
      collected.push(...batch);
      feedStats.push({ url: feed.url, kind: feed.kind, ok: true, count: batch.length });
    } catch (err) {
      feedStats.push({ url: feed.url, kind: feed.kind, ok: false, error: String(err.message || err) });
    }
  }
  return { collected, feedStats };
}

export function rankItems(deduped, modelInfo, topics, threshold, maxItems) {
  return deduped
    .map((it) => ({
      ...it,
      score: Number(it.score) || 5,
      ai_summary: it.ai_summary || String(it.summary || '').slice(0, 200),
    }))
    .filter((it) => !modelInfo.ai_ok || it.score >= threshold)
    .sort((a, b) => b.score - a.score)
    .slice(0, maxItems);
}

export function formatDigest(mode, ranked, modelInfo) {
  const today = new Date().toISOString().slice(0, 10);
  const aiLabel = modelInfo.ai_ok
    ? `${modelInfo.provider}${modelInfo.model ? ` (${modelInfo.model})` : ''}`
    : 'off';
  const header =
    mode === 'papers'
      ? `Weekly Research Papers — ${today}\nAI: ${aiLabel}\n`
      : `Daily Research News — ${today}\nAI: ${aiLabel}\n`;

  if (!ranked.length) {
    return header + '\nNo new items matched your topics.';
  }
  const lines = ranked.map((it, i) => {
    const sum = it.ai_summary || String(it.summary || '').slice(0, 200);
    return `${i + 1}. ${it.title} (${it.score}/10)\n${sum}\n${it.source} — ${it.url}`;
  });
  return `${header}\n${lines.join('\n\n')}`;
}

export function chunkMessage(text, maxLen = 3900) {
  const chunks = [];
  let rest = String(text || '');
  while (rest.length > maxLen) {
    let cut = rest.lastIndexOf('\n\n', maxLen);
    if (cut < maxLen * 0.5) cut = maxLen;
    chunks.push(rest.slice(0, cut).trim());
    rest = rest.slice(cut).trim();
  }
  if (rest) chunks.push(rest);
  return chunks.length ? chunks : ['(empty)'];
}
