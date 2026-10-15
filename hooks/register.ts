import type { EngineInterface, Register } from 'claude-code'
import { liveExcusePrompt, subjectOf, templateExcuse } from './excuses'

const BASE = 'http://127.0.0.1:47391'
const MAX_TYPED = 40 // longer inserts are pastes: no card per character
const MAX_TITLE = 300

// Shown until the model's own excuses for this prompt arrive.
const STOCK_EXCUSES = [
  'ただいま全力で考えております',
  '銭形警部に追われておりまして',
  'コーヒーを淹れ直しております',
  'トークンを一枚ずつ数えております',
  '念のため、もう一度読み直しております',
  'いい感じの言い回しを探しております',
  '今、ちょうどいいところなんです',
  'キャッシュが温まるのを待っております',
]

const EXCUSE_PROMPT = (prompt: string) =>
  `次の依頼を受けたアシスタントが、返事に時間がかかっている言い訳を8個書いてください。
依頼の内容にちなんだ、ユーモアのある日本語で、1つ25文字以内。
1行に1つ、番号や記号や引用符は付けず、言い訳の文だけを書いてください。

依頼:
${prompt.slice(0, 600)}`

let sessionId: string | undefined
let enabled = true
let currentRequest = ''
let thinking = false
let haikuBusy = false

async function post($: EngineInterface, path: string, body: string) {
  if (!enabled) return
  try {
    await $.http.fetch(`${BASE}${path}`, { method: 'POST', body })
  } catch {
    await launch($)
    await $.http.fetch(`${BASE}${path}`, { method: 'POST', body }).catch(() => undefined)
  }
}

async function ensureHelper($: EngineInterface) {
  const up = await $.http.fetch(`${BASE}/ping`).then(r => r.ok, () => false)
  if (!up) await launch($)
}

// The helper is shared by every session; one that finds the port taken exits.
async function launch($: EngineInterface) {
  const root = $.plugin.root
  await $.process
    .run(['/bin/sh', '-c', `nohup "$0/helper/lupin-overlay" "$0/sounds" >/dev/null 2>&1 &`, root])
    .catch(() => undefined)
  await $.clock.sleep(400)
}

function shuffled<T>(items: readonly T[]): T[] {
  const out = [...items]
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    ;[out[i], out[j]] = [out[j]!, out[i]!]
  }
  return out
}

async function writeExcuses($: EngineInterface, id: string, prompt: string) {
  const reply = await $.model.complete({ model: 'haiku', prompt: EXCUSE_PROMPT(prompt), maxTokens: 600 })
  if (!reply.isAnswered) return
  const excuses = reply.text
    .split('\n')
    .map(line => line.replace(/^\s*(?:\d+[.)．、]|[-・*])\s*/, '').replace(/^["「]|["」]$/g, '').trim())
    .filter(line => line.length > 0 && line.length <= 40)
  if (excuses.length > 0) await post($, '/think/excuses', JSON.stringify({ id, excuses }))
}

async function liveExcuse($: EngineInterface, tool: string, input: Record<string, unknown>) {
  const id = sessionId ?? 'session'
  const subject = subjectOf(tool, input)
  await post($, '/think/now', JSON.stringify({ id, excuse: templateExcuse(tool, subject) }))
  if (haikuBusy) return // one at a time: a burst of calls keeps its templates
  haikuBusy = true
  try {
    const reply = await $.model.complete({ model: 'haiku', prompt: liveExcusePrompt(tool, subject, currentRequest), maxTokens: 100 })
    const line = reply.isAnswered ? reply.text.trim().split('\n')[0]?.replace(/^["「]|["」]$/g, '').trim() : undefined
    if (thinking && line && line.length <= 40) await post($, '/think/now', JSON.stringify({ id, excuse: line }))
  } finally {
    haikuBusy = false
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    sessionId = await $.session.id()
    enabled = (await $.store.get('enabled')) !== false
    await $.command.register({
      name: 'lupin',
      description: 'ルパン風タイトル演出のオン／オフ',
      argumentHint: 'on | off',
    })
    if (enabled) await ensureHelper($)
    return next(e)
  })

  on('command.run', { command: 'lupin' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    if (arg === 'off') {
      enabled = false
      thinking = false
      await $.store.set('enabled', false)
      await $.http.fetch(`${BASE}/quit`, { method: 'POST', body: '' }).catch(() => undefined)
      return { text: 'ルパン演出をオフにしました（ヘルパーも終了）。/lupin on で再開します。' }
    }
    if (arg === 'on') {
      enabled = true
      await $.store.set('enabled', true)
      await ensureHelper($)
      return { text: 'ルパン演出をオンにしました。/lupin off で止まります。' }
    }
    return { text: `ルパン演出は${enabled ? 'オン' : 'オフ'}です。/lupin on か /lupin off で切り替えます。` }
  })

  on('prompt.edit', async ($, e, next) => {
    const box = await next(e)
    if (!enabled) return box
    const typed = e.inputText
    if (typed.length > 0 && typed.length <= MAX_TYPED) void post($, '/char', typed)
    return box
  })

  on('prompt.submit', async ($, e, next) => {
    const text = e.text.trim()
    if (enabled && e.command === undefined && text.length > 0) {
      const shown = text.length > MAX_TITLE ? `${text.slice(0, MAX_TITLE)}…` : text
      const id = sessionId ?? 'session'
      currentRequest = text
      thinking = true
      void post($, '/title', shown)
        .then(() => post($, '/think/start', JSON.stringify({ id, excuses: shuffled(STOCK_EXCUSES) })))
        .then(() => writeExcuses($, id, text))
        .catch(() => undefined)
    }
    return next(e)
  })

  // Whatever runs now, the main loop's or a subagent's, gets its own excuse.
  on('tool.call', async ($, e, next) => {
    if (thinking) void liveExcuse($, String(e.tool), e as unknown as Record<string, unknown>).catch(() => undefined)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined) thinking = false
    if (e.agentId === undefined) void post($, '/think/stop', JSON.stringify({ id: sessionId ?? 'session' }))
    return result
  })
}
