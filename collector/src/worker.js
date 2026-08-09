/**
 * Hosted collection + labeling backend for the parse benchmark.
 *
 * Always-on version of benchmark/labeling/server.py, plus photo upload.
 * Storage is a single R2 bucket:
 *
 *   images/<stem>.jpg      normalized JPEG (client downscales before upload)
 *   originals/<stem>.<ext> full-resolution original of a field upload
 *   labels/<stem>.json     ground-truth label, same schema as benchmark/labels/
 *   meta/<stem>.json       upload provenance: who, when, note, original ext
 *   claims/<stem>          soft lock while someone is labeling (30 min TTL)
 *
 * Every /api route requires the shared passcode in the X-Passcode header.
 * Labels carry a summary in R2 customMetadata so the dashboard is one LIST
 * call instead of one GET per label.
 *
 * benchmark/scripts/sync_remote.py pushes the local set up and pulls
 * contributions back down; the repo stays the source of record.
 */

import APP_HTML from "./app.html";

const CLAIM_TTL_MS = 30 * 60 * 1000;
const MAX_IMAGE_BYTES = 8 * 1024 * 1024; // normalized JPEGs are ~300-600KB
const MAX_ORIGINAL_BYTES = 30 * 1024 * 1024;
const SAFE_STEM = /^[a-zA-Z0-9._-]+$/;
const ORIGINAL_EXTS = { jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", webp: "image/webp", heic: "image/heic", heif: "image/heif" };

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });

const err = (message, status) => json({ error: message }, status);

function passcodeOk(request, env) {
  const given = request.headers.get("X-Passcode") || "";
  const want = env.PASSCODE || "";
  if (!want || given.length !== want.length) return false;
  let diff = 0;
  for (let i = 0; i < want.length; i++) diff |= given.charCodeAt(i) ^ want.charCodeAt(i);
  return diff === 0;
}

/** Summary stored as customMetadata on labels/<stem>.json so the dashboard
 *  needs only a LIST. Values must survive HTTP headers, so names are
 *  URI-encoded. */
function labelMetadata(label, meta) {
  const itemCount = (label.sections || []).reduce((n, s) => n + ((s.items || []).length), 0);
  return {
    labeled: label.labeled ? "1" : "0",
    verified: label.verified ? "1" : "0",
    labeled_by: encodeURIComponent(label.labeled_by || ""),
    provenance: (label.attributes || {}).provenance || "",
    item_count: String(itemCount),
    uploaded_by: encodeURIComponent((meta && meta.uploaded_by) || ""),
  };
}

async function putLabel(env, stem, label, meta) {
  await env.BUCKET.put(`labels/${stem}.json`, JSON.stringify(label, null, 2) + "\n", {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
    customMetadata: labelMetadata(label, meta),
  });
}

async function getJSON(env, key) {
  const obj = await env.BUCKET.get(key);
  return obj ? await obj.json() : null;
}

function labelStub(stem, sourceFile, provenance, note) {
  return {
    image: `${stem}.jpg`,
    source_file: sourceFile,
    labeled: false,
    attributes: {
      provenance,
      orientation: null,
      script: null,
      surface: null,
      lighting: null,
      angle: null,
      blur: null,
      columns: null,
    },
    sections: [{ header_ja: null, items: [] }],
    decorative_text: [],
    notes: note ? `[from uploader] ${note}` : "",
  };
}

async function listAll(env, prefix, include) {
  const objects = [];
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix, cursor, include: include || [] });
    objects.push(...page.objects);
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return objects;
}

async function activeClaims(env, ctx) {
  const now = Date.now();
  const out = {};
  for (const obj of await listAll(env, "claims/", ["customMetadata"])) {
    const stem = obj.key.slice("claims/".length);
    const ts = Number(obj.customMetadata?.ts || 0);
    if (now - ts > CLAIM_TTL_MS) {
      ctx.waitUntil(env.BUCKET.delete(obj.key));
    } else {
      out[stem] = decodeURIComponent(obj.customMetadata?.labeler || "");
    }
  }
  return out;
}

async function state(env, ctx) {
  const claims = await activeClaims(env, ctx);
  const metas = new Map();
  for (const obj of await listAll(env, "meta/", ["customMetadata"])) {
    metas.set(obj.key.slice("meta/".length).replace(/\.json$/, ""), obj.customMetadata || {});
  }
  const rows = [];
  for (const obj of await listAll(env, "labels/", ["customMetadata"])) {
    const stem = obj.key.slice("labels/".length).replace(/\.json$/, "");
    const md = obj.customMetadata || {};
    rows.push({
      stem,
      image: `${stem}.jpg`,
      labeled: md.labeled === "1",
      verified: md.verified === "1",
      labeled_by: decodeURIComponent(md.labeled_by || "") || null,
      provenance: md.provenance || null,
      item_count: Number(md.item_count || 0),
      uploaded_by: decodeURIComponent(md.uploaded_by || metas.get(stem)?.uploaded_by || "") || null,
      claimed_by: claims[stem] || null,
    });
  }
  rows.sort((a, b) => a.stem.localeCompare(b.stem));
  return {
    images: rows,
    counts: {
      total: rows.length,
      labeled: rows.filter((r) => r.labeled).length,
      verified: rows.filter((r) => r.verified).length,
      field: rows.filter((r) => r.provenance === "field").length,
    },
  };
}

function newStem(provenance) {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  const stamp = `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}-${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}`;
  const rand = [...crypto.getRandomValues(new Uint8Array(2))].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${provenance}-${stamp}-${rand}`;
}

async function handleUpload(request, env, url) {
  const uploader = (url.searchParams.get("uploader") || "").trim().slice(0, 60);
  const note = (url.searchParams.get("note") || "").trim().slice(0, 500);
  const filename = (url.searchParams.get("filename") || "").slice(0, 120);
  const provenance = url.searchParams.get("provenance") === "web" ? "web" : "field";
  if (!uploader) return err("uploader name required", 400);

  const body = await request.arrayBuffer();
  if (body.byteLength < 1024) return err("image too small — did the upload fail?", 400);
  if (body.byteLength > MAX_IMAGE_BYTES) return err("normalized image too large", 413);

  const stem = newStem(provenance);
  const meta = {
    uploaded_by: uploader,
    uploaded_at: new Date().toISOString(),
    source_file: filename || `${stem}.jpg`,
    note: note || null,
    original_ext: null,
  };
  await env.BUCKET.put(`images/${stem}.jpg`, body, {
    httpMetadata: { contentType: "image/jpeg" },
  });
  await env.BUCKET.put(`meta/${stem}.json`, JSON.stringify(meta, null, 2), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
    customMetadata: { uploaded_by: encodeURIComponent(uploader) },
  });
  const label = labelStub(stem, meta.source_file, provenance, note);
  await putLabel(env, stem, label, meta);
  return json({ stem });
}

async function handleUploadOriginal(request, env, stem, url) {
  const ext = (url.searchParams.get("ext") || "jpg").toLowerCase();
  const contentType = ORIGINAL_EXTS[ext];
  if (!contentType) return err("unsupported original extension", 400);
  const meta = await getJSON(env, `meta/${stem}.json`);
  if (!meta) return err("unknown upload", 404);
  const body = await request.arrayBuffer();
  if (body.byteLength > MAX_ORIGINAL_BYTES) return err("original too large", 413);
  await env.BUCKET.put(`originals/${stem}.${ext}`, body, { httpMetadata: { contentType } });
  meta.original_ext = ext;
  await env.BUCKET.put(`meta/${stem}.json`, JSON.stringify(meta, null, 2), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
    customMetadata: { uploaded_by: encodeURIComponent(meta.uploaded_by || "") },
  });
  return json({ ok: true });
}

async function handleSaveLabel(env, stem, body) {
  const existing = await getJSON(env, `labels/${stem}.json`);
  if (!existing) return err("not found", 404);
  const label = body.label;
  const labeler = (body.labeler || "").trim().slice(0, 60);
  if (!label || typeof label !== "object" || !Array.isArray(label.sections)) {
    return err("label with sections[] required", 400);
  }
  // Preserve identity fields; the client edits content, not identity.
  label.image = existing.image;
  label.source_file = existing.source_file;
  label.labeled = true;
  label.labeled_by = labeler || existing.labeled_by || null;
  // Any content edit invalidates prior verification.
  label.verified = false;
  const meta = await getJSON(env, `meta/${stem}.json`);
  await putLabel(env, stem, label, meta);
  await env.BUCKET.delete(`claims/${stem}`);
  return json({ ok: true });
}

/** Sync manifest: everything the pull/push script needs in one call.
 *  R2 etags are content MD5 for single-part uploads, which is how the sync
 *  script skips unchanged files. */
async function syncManifest(env) {
  const strip = (obj, prefix) => ({
    key: obj.key.slice(prefix.length),
    size: obj.size,
    etag: obj.etag,
  });
  const [labels, images, originals, metas] = await Promise.all([
    listAll(env, "labels/", ["customMetadata"]),
    listAll(env, "images/"),
    listAll(env, "originals/"),
    listAll(env, "meta/"),
  ]);
  return json({
    labels: labels.map((o) => ({
      ...strip(o, "labels/"),
      labeled: o.customMetadata?.labeled === "1",
      verified: o.customMetadata?.verified === "1",
    })),
    images: images.map((o) => strip(o, "images/")),
    originals: originals.map((o) => strip(o, "originals/")),
    meta: metas.map((o) => strip(o, "meta/")),
  });
}

async function serveObject(env, key, contentType) {
  const obj = await env.BUCKET.get(key);
  if (!obj) return err("not found", 404);
  return new Response(obj.body, {
    headers: {
      "Content-Type": contentType || obj.httpMetadata?.contentType || "application/octet-stream",
      "Cache-Control": "no-store",
    },
  });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/" || path === "/index.html") {
      return new Response(APP_HTML, {
        headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" },
      });
    }
    if (!path.startsWith("/api/")) return err("not found", 404);

    if (path === "/api/ping") {
      // Lets the gate page validate a passcode without leaking anything else.
      return passcodeOk(request, env) ? json({ ok: true }) : err("bad passcode", 401);
    }
    if (!passcodeOk(request, env)) return err("bad passcode", 401);

    const seg = path.slice("/api/".length).split("/");
    const stem = seg.length > 1 ? seg[seg.length - 1] : "";
    if (seg.length > 1 && !SAFE_STEM.test(stem)) return err("bad name", 400);

    // --- reads ---
    if (request.method === "GET") {
      if (path === "/api/state") return json(await state(env, ctx));
      if (path === "/api/sync/manifest") return syncManifest(env);
      if (seg[0] === "sync" && seg[1] === "label") {
        // Raw stored bytes, so the sync script's md5-vs-etag comparison works.
        return serveObject(env, `labels/${stem}`, "application/json; charset=utf-8");
      }
      if (seg[0] === "label") {
        const label = await getJSON(env, `labels/${stem}.json`);
        return label ? json(label) : err("not found", 404);
      }
      if (seg[0] === "meta") {
        const meta = await getJSON(env, `meta/${stem}.json`);
        return meta ? json(meta) : err("not found", 404);
      }
      if (seg[0] === "image") return serveObject(env, `images/${stem}`, "image/jpeg");
      if (seg[0] === "original") {
        const base = stem.replace(/\.[a-z0-9]+$/, "");
        const meta = await getJSON(env, `meta/${base}.json`);
        if (!meta || !meta.original_ext) return err("no original", 404);
        return serveObject(env, `originals/${base}.${meta.original_ext}`);
      }
      return err("not found", 404);
    }

    if (request.method === "POST") {
      if (path === "/api/upload") return handleUpload(request, env, url);
      if (seg[0] === "upload-original") return handleUploadOriginal(request, env, stem, url);

      if (path === "/api/claim") {
        const body = await request.json().catch(() => ({}));
        const labeler = (body.labeler || "").trim().slice(0, 60);
        if (!labeler) return err("name required", 400);
        const claims = await activeClaims(env, ctx);
        const rows = (await state(env, ctx)).images;
        for (const row of rows) {
          if (row.labeled || claims[row.stem]) continue;
          await env.BUCKET.put(`claims/${row.stem}`, "", {
            customMetadata: { labeler: encodeURIComponent(labeler), ts: String(Date.now()) },
          });
          return json({ stem: row.stem });
        }
        return json({ stem: null });
      }
      if (path === "/api/release") {
        const body = await request.json().catch(() => ({}));
        const s = body.stem || "";
        if (SAFE_STEM.test(s)) await env.BUCKET.delete(`claims/${s}`);
        return json({ ok: true });
      }
      if (seg[0] === "label") {
        const body = await request.json().catch(() => ({}));
        return handleSaveLabel(env, stem, body);
      }
      if (seg[0] === "verify") {
        const body = await request.json().catch(() => ({}));
        const existing = await getJSON(env, `labels/${stem}.json`);
        if (!existing) return err("not found", 404);
        existing.verified = Boolean(body.verified);
        const meta = await getJSON(env, `meta/${stem}.json`);
        await putLabel(env, stem, existing, meta);
        return json({ ok: true });
      }
      return err("not found", 404);
    }

    if (request.method === "PUT") {
      // Sync pushes from the repo. The script pulls first and skips conflicts;
      // the server just stores what it is sent.
      if (seg[0] === "sync" && seg[1] === "label") {
        // Store the raw bytes so the object's etag equals the repo file's md5.
        const text = await request.text();
        let label;
        try { label = JSON.parse(text); } catch { return err("label JSON required", 400); }
        if (!label || !Array.isArray(label.sections)) return err("label JSON required", 400);
        const base = stem.replace(/\.json$/, "");
        const meta = await getJSON(env, `meta/${base}.json`);
        await env.BUCKET.put(`labels/${base}.json`, text, {
          httpMetadata: { contentType: "application/json; charset=utf-8" },
          customMetadata: labelMetadata(label, meta),
        });
        return json({ ok: true });
      }
      if (seg[0] === "sync" && seg[1] === "image") {
        const body = await request.arrayBuffer();
        if (body.byteLength > MAX_IMAGE_BYTES) return err("too large", 413);
        await env.BUCKET.put(`images/${stem}`, body, { httpMetadata: { contentType: "image/jpeg" } });
        return json({ ok: true });
      }
      return err("not found", 404);
    }

    if (request.method === "DELETE") {
      // Remove a mistaken upload (blurry, duplicate). Only unlabeled uploads.
      if (seg[0] === "upload") {
        const label = await getJSON(env, `labels/${stem}.json`);
        if (!label) return err("not found", 404);
        if (label.labeled) return err("already labeled — refuse to delete", 409);
        const meta = await getJSON(env, `meta/${stem}.json`);
        if (!meta) return err("not an upload — sync-pushed images are deleted from the repo", 409);
        await Promise.all([
          env.BUCKET.delete(`images/${stem}.jpg`),
          env.BUCKET.delete(`labels/${stem}.json`),
          env.BUCKET.delete(`meta/${stem}.json`),
          env.BUCKET.delete(`claims/${stem}`),
          meta.original_ext ? env.BUCKET.delete(`originals/${stem}.${meta.original_ext}`) : Promise.resolve(),
        ]);
        return json({ ok: true });
      }
      return err("not found", 404);
    }

    return err("method not allowed", 405);
  },
};
