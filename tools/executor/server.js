#!/usr/bin/env node
/**
 * Exécuteur HTTP local — pont entre le Master Agent et Antigravity CLI (agy).
 *
 * Zéro dépendance : Node >= 18 suffit.
 *
 *   GET  /health                  → vivant, version, exécuteur détecté
 *   GET  /status                  → job courant + file d'attente
 *   GET  /jobs                    → historique
 *   GET  /jobs/:id                → détail + fin du log
 *   POST /pass                    → { id, spec, base? }  lance une passe
 *   POST /command                 → { name, args? }      commande en liste blanche
 *
 * Authentification : en-tête `Authorization: Bearer $EXECUTOR_TOKEN` sur toutes
 * les routes sauf /health. Sans EXECUTOR_TOKEN défini, le serveur refuse de démarrer.
 */

'use strict';

const http = require('node:http');
const { spawn, execFile } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

// ------------------------------------------------------------------ config
const CFG = {
  port: Number(process.env.PORT || 7788),
  host: process.env.HOST || '127.0.0.1',
  token: process.env.EXECUTOR_TOKEN || '',
  repoRoot: process.env.REPO_ROOT || process.cwd(),
  baseBranch: process.env.BASE_BRANCH || 'main',
  maxLogTail: Number(process.env.MAX_LOG_TAIL || 400),
  jobTimeoutMs: Number(process.env.JOB_TIMEOUT_MS || 45 * 60 * 1000),
};

if (!CFG.token || CFG.token.length < 24) {
  console.error('EXECUTOR_TOKEN manquant ou trop court (>= 24 caractères). Voir .env.example.');
  process.exit(1);
}

const DIRS = {
  logs: path.join(CFG.repoRoot, 'tools', 'executor', 'logs'),
  passes: path.join(CFG.repoRoot, '.agent', 'passes'),
  runner: path.join(CFG.repoRoot, 'tools', 'executor', 'run-pass.sh'),
};
fs.mkdirSync(DIRS.logs, { recursive: true });
fs.mkdirSync(DIRS.passes, { recursive: true });

/**
 * Liste blanche de commandes. C'est la frontière de sécurité du serveur :
 * aucune chaîne fournie par l'appelant n'atteint jamais un shell.
 * Pour ajouter une capacité, ajoute une entrée ici — jamais un passe-plat.
 */
const COMMANDS = {
  test:      { cmd: 'npm',  args: ['test', '--silent'] },
  lint:      { cmd: 'npm',  args: ['run', 'lint', '--silent'] },
  typecheck: { cmd: 'npm',  args: ['run', 'typecheck', '--silent'] },
  build:     { cmd: 'npm',  args: ['run', 'build', '--silent'] },
  digest:    { cmd: 'bash', args: ['tools/digest.sh'] },
  'git-log': { cmd: 'git',  args: ['log', '--oneline', '--decorate', '-40'] },
  'git-status': { cmd: 'git', args: ['status', '--porcelain=v1', '-b'] },
  branches:  { cmd: 'git',  args: ['branch', '-a', '--sort=-committerdate'] },
  tree:      { cmd: 'git',  args: ['ls-files'] },
  'agy-version': { cmd: 'agy', args: ['--version'] },
};

// ------------------------------------------------------------------ état
const state = { current: null, queue: [], jobs: new Map() };
const newId = () => crypto.randomBytes(6).toString('hex');

function tail(file, n = CFG.maxLogTail) {
  try {
    return fs.readFileSync(file, 'utf8').split('\n').slice(-n).join('\n');
  } catch { return ''; }
}

function publicJob(j) {
  if (!j) return null;
  const { child, ...rest } = j;
  return rest;
}

// ------------------------------------------------------------------ exécution
function runPass(job) {
  state.current = job;
  job.status = 'running';
  job.startedAt = new Date().toISOString();

  const specPath = path.join(DIRS.passes, `${job.passId}.md`);
  fs.writeFileSync(specPath, job.spec, 'utf8');
  job.specPath = specPath;

  const child = spawn('bash', [DIRS.runner, job.passId, specPath, job.base], {
    cwd: CFG.repoRoot,
    env: { ...process.env, REPO_ROOT: CFG.repoRoot, BASE_BRANCH: job.base },
  });
  job.child = child;

  let out = '', err = '';
  child.stdout.on('data', (d) => { out += d; });
  child.stderr.on('data', (d) => { err += d; job.progress = d.toString().trim().split('\n').pop(); });

  const killer = setTimeout(() => {
    job.timedOut = true;
    try { child.kill('SIGKILL'); } catch {}
  }, CFG.jobTimeoutMs);

  child.on('close', (code) => {
    clearTimeout(killer);
    job.finishedAt = new Date().toISOString();
    job.exitCode = code;
    job.stderrTail = err.split('\n').slice(-40).join('\n');

    // Le runner émet une ligne JSON en dernier. Le code de sortie n'est pas fiable.
    const jsonLine = out.trim().split('\n').filter((l) => l.trim().startsWith('{')).pop();
    if (jsonLine) {
      try { job.result = JSON.parse(jsonLine); } catch { job.result = { raw: jsonLine }; }
    }
    job.status = job.timedOut ? 'timeout' : (job.result?.status || (code === 0 ? 'done' : 'failed'));
    job.logTail = tail(path.join(DIRS.logs, `${job.passId}.log`));

    delete job.child;
    state.current = null;
    if (state.queue.length) runPass(state.queue.shift());
  });
}

function runCommand(name, extra = []) {
  return new Promise((resolve) => {
    const spec = COMMANDS[name];
    if (!spec) return resolve({ ok: false, error: `commande inconnue : ${name}` });
    const safeExtra = extra.filter((a) => typeof a === 'string' && /^[\w.\/=@:-]{1,80}$/.test(a));
    execFile(spec.cmd, [...spec.args, ...safeExtra], {
      cwd: CFG.repoRoot, timeout: 10 * 60 * 1000, maxBuffer: 8 * 1024 * 1024,
    }, (e, stdout, stderr) => {
      resolve({
        ok: !e,
        command: `${spec.cmd} ${[...spec.args, ...safeExtra].join(' ')}`,
        exitCode: e?.code ?? 0,
        stdout: String(stdout).split('\n').slice(-CFG.maxLogTail).join('\n'),
        stderr: String(stderr).split('\n').slice(-80).join('\n'),
      });
    });
  });
}

// ------------------------------------------------------------------ http
function send(res, code, body) {
  const payload = JSON.stringify(body, null, 2);
  res.writeHead(code, { 'content-type': 'application/json; charset=utf-8' });
  res.end(payload);
}

function authorized(req) {
  const h = req.headers.authorization || '';
  const given = h.startsWith('Bearer ') ? h.slice(7) : '';
  const a = Buffer.from(given), b = Buffer.from(CFG.token);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let raw = '';
    req.on('data', (c) => {
      raw += c;
      if (raw.length > 2_000_000) { reject(new Error('corps trop volumineux')); req.destroy(); }
    });
    req.on('end', () => {
      if (!raw) return resolve({});
      try { resolve(JSON.parse(raw)); } catch { reject(new Error('JSON invalide')); }
    });
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const route = `${req.method} ${url.pathname}`;

  if (route === 'GET /health') {
    return send(res, 200, {
      ok: true, service: 'antigravity-executor', version: 1,
      repo: CFG.repoRoot, baseBranch: CFG.baseBranch,
      busy: Boolean(state.current), queued: state.queue.length,
    });
  }

  if (!authorized(req)) return send(res, 401, { error: 'non autorisé' });

  try {
    if (route === 'GET /status') {
      return send(res, 200, {
        current: publicJob(state.current),
        queue: state.queue.map((j) => ({ id: j.id, passId: j.passId })),
        recent: [...state.jobs.values()].slice(-10).map((j) => ({
          id: j.id, passId: j.passId, status: j.status, finishedAt: j.finishedAt,
        })),
      });
    }

    if (route === 'GET /jobs') {
      return send(res, 200, { jobs: [...state.jobs.values()].map(publicJob) });
    }

    if (req.method === 'GET' && url.pathname.startsWith('/jobs/')) {
      const job = state.jobs.get(url.pathname.split('/')[2]);
      if (!job) return send(res, 404, { error: 'job inconnu' });
      return send(res, 200, {
        ...publicJob(job),
        logTail: job.logTail || tail(path.join(DIRS.logs, `${job.passId}.log`)),
      });
    }

    if (route === 'POST /pass') {
      const body = await readBody(req);
      const passId = String(body.id || '').trim();
      const spec = String(body.spec || '');
      if (!/^PASS-[A-Za-z0-9_.-]{1,32}$/.test(passId)) {
        return send(res, 400, { error: 'id invalide, format attendu : PASS-001' });
      }
      if (spec.length < 40) return send(res, 400, { error: 'spec trop courte' });

      const job = {
        id: newId(), passId, spec,
        base: String(body.base || CFG.baseBranch),
        status: 'queued', queuedAt: new Date().toISOString(),
      };
      state.jobs.set(job.id, job);
      if (state.current) state.queue.push(job); else runPass(job);
      return send(res, 202, { accepted: true, jobId: job.id, passId, status: job.status });
    }

    if (route === 'POST /command') {
      const body = await readBody(req);
      const result = await runCommand(String(body.name || ''), Array.isArray(body.args) ? body.args : []);
      return send(res, result.ok === false && result.error ? 400 : 200, result);
    }

    return send(res, 404, { error: 'route inconnue', routes: [
      'GET /health', 'GET /status', 'GET /jobs', 'GET /jobs/:id', 'POST /pass', 'POST /command',
    ] });
  } catch (e) {
    return send(res, 400, { error: e.message });
  }
});

server.listen(CFG.port, CFG.host, () => {
  console.log(`exécuteur à l'écoute sur http://${CFG.host}:${CFG.port}`);
  console.log(`dépôt : ${CFG.repoRoot}   branche de base : ${CFG.baseBranch}`);
  console.log(`commandes autorisées : ${Object.keys(COMMANDS).join(', ')}`);
  console.log('expose-le ensuite avec :  cloudflared tunnel --url http://' + CFG.host + ':' + CFG.port);
});
