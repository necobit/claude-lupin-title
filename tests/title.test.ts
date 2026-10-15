import { expect, mock, test } from 'claude-code/testing'

function recordFetches(on: Parameters<typeof mock.env>[0]) {
  const sent: { url: string; body?: string }[] = []
  on('http.fetch', async (_$, e) => {
    sent.push({ url: e.url, body: e.init?.body })
    return { value: { status: 200, ok: true, headers: {}, text: 'ok' } } as never
  })
  return sent
}

test('the end of a turn stops the thinking card', async ($, on) => {
  mock.clock(on)
  const sent = recordFetches(on)
  on('turn.complete', () => ({ text: '' }))
  await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't', reason: 'answer' } as never)
  await new Promise(r => setTimeout(r, 0))
  expect(sent.map(s => s.url.endsWith('/think/stop'))).toContain(true)
})

test('a typed character goes to /char, a sent prompt to /title', async ($, on) => {
  mock.clock(on)
  const sent = recordFetches(on)
  on('prompt.edit', (_$, e) => ({ text: e.text + e.inputText, cursor: e.cursor + 1 }) as never)
  on('prompt.submit', (_$, e) => ({ text: e.text }))

  await $.prompt.edit({ origin: { kind: 'composer' }, text: '', cursor: 0, start: 0, end: 0, inputText: 'ル' } as never)
  await $.prompt.submit({ text: '  ルパン三世  ' } as never)

  await new Promise(r => setTimeout(r, 0))
  const paths = sent.map(s => s.url.replace('http://127.0.0.1:47391', ''))
  expect(paths.slice(0, 3)).toEqual(['/char', '/title', '/think/start'])
  expect(sent[1]?.body).toBe('ルパン三世')
  expect(JSON.parse(sent[2]?.body ?? '{}').excuses.length).toBe(8)
})
