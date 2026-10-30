#!/usr/bin/env node
/** Research digest pipeline — reads .run-input.json, writes latest.json + latest.txt */
import fs from 'node:fs';
import path from 'node:path';
import {
  fetchItems,
  dedupeItems,
  resolveModel,
  scoreBatch,
  rankItems,
  formatDigest,
  chunkMessage,
  httpJson,
} from './pipeline_lib.mjs';

const OUT_DIR = process.env.RD_OUT_DIR || '/files/research-digest';
const INPUT = process.env.RD_INPUT || path.join(OUT_DIR, '.run-input.json');

async function maybeNotify(notifierUrl, message, source) {
  if (!notifierUrl) return { skipped: true };
  try {
    await httpJson('POST', notifierUrl, { message, source }, 15000);
    return { ok: true };
  } catch (err) {
    return { ok: false, error: String(err.message || err) };
  }
}

async function main() {
  const input = JSON.parse(fs.readFileSync(INPUT, 'utf8'));
  const mode = input.mode || 'news';
  const payload = input.payload || input;
  const config = payload.config || {};
  const topics = Array.isArray(payload.topics) ? payload.topics : [];
  const feeds = Array.isArray(payload.feeds) ? payload.feeds : [];
  const seen = Array.isArray(payload.seen) ? payload.seen : [];
  const threshold = Number(config.relevance_threshold || 6);
  const maxItems = Number(config.max_items || 8);
  const delivery = String(config.delivery_mode || 'file');
  const notifierUrl = delivery.includes('notify')
    ? String(config.notifier_url || 'http://host.docker.internal:8001/notify')
    : '';

  fs.mkdirSync(OUT_DIR, { recursive: true });

  const { collected, feedStats } = await fetchItems(mode, feeds, 6);
  const deduped = dedupeItems(collected, seen, 16);
  const modelInfo = await resolveModel(config);

  let scored = deduped.map((x) => ({ ...x, score: 5, ai_summary: '' }));
  let aiDebug = { skipped: true };

  if (modelInfo.ai_ok && deduped.length) {
    const toScore = deduped.slice(0, 4);
    scored = toScore.map((x) => ({ ...x, score: 5, ai_summary: '' }));
    try {
      aiDebug = await scoreBatch(scored, topics, modelInfo);
      aiDebug.skipped = false;
    } catch (err) {
      aiDebug = { skipped: false, error: String(err.message || err) };
      for (const b of scored) {
        b.ai_summary = String(b.summary || '').slice(0, 200);
      }
    }
  }

  const ranked = rankItems(scored, modelInfo, topics, threshold, maxItems);
  const digestText = formatDigest(mode, ranked, modelInfo);
  const chunks = chunkMessage(digestText);

  const result = {
    ok: true,
    mode,
    model: modelInfo,
    stats: {
      feeds: feedStats,
      collected: collected.length,
      deduped: deduped.length,
      ranked: ranked.length,
    },
    ai_debug: aiDebug,
    items: ranked,
    digest_text: digestText,
    chunks,
  };

  fs.writeFileSync(path.join(OUT_DIR, 'latest.json'), JSON.stringify(result, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, 'latest.txt'), digestText);

  if (delivery.includes('notify')) {
    const notifyResults = [];
    for (let i = 0; i < chunks.length; i++) {
      const prefix = chunks.length > 1 ? `[${i + 1}/${chunks.length}] ` : '';
      notifyResults.push(await maybeNotify(notifierUrl, prefix + chunks[i], 'research-digest'));
    }
    result.notify = notifyResults;
  }

  console.log(JSON.stringify(result));
}

main().catch((err) => {
  const fail = { ok: false, error: String(err.message || err) };
  try {
    fs.mkdirSync(OUT_DIR, { recursive: true });
    fs.writeFileSync(path.join(OUT_DIR, 'latest.json'), JSON.stringify(fail, null, 2));
  } catch (_) {}
  console.log(JSON.stringify(fail));
  process.exit(1);
});
