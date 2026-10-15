import { expect, test } from 'claude-code/testing'
import { subjectOf, templateExcuse } from '../hooks/excuses'

test('a tool call becomes a subject and an excuse about it', async () => {
  expect(subjectOf('Bash', { command: 'npm install --save foo' })).toBe('npm install')
  expect(subjectOf('Read', { file_path: '/a/b/platformio.ini' })).toBe('platformio.ini')
  expect(templateExcuse('Read', 'platformio.ini')).toContain('platformio.ini')
  expect(templateExcuse('Mystery', '')).toContain('Mystery')
})

test('a tool call while thinking posts a live excuse', async ($, on) => {
  const sent: string[] = []
  on('http.fetch', async (_$, e) => {
    sent.push(`${e.url.replace('http://127.0.0.1:47391', '')} ${e.init?.body ?? ''}`)
    return { value: { status: 200, ok: true, headers: {}, text: 'ok' } } as never
  })
  on('prompt.submit', (_$, e) => ({ text: e.text }))
  on('tool.call', () => ({ result: { text: 'done' } }) as never)
  on('model.complete', () => ({ value: { isAnswered: false, reason: 'empty-reply' } }) as never)
  await $.prompt.submit({ text: 'ビルドして' } as never)
  await $.tool.call({ tool: 'Read', file_path: '/x/platformio.ini' } as never).catch(() => undefined)
  await new Promise(r => setTimeout(r, 0))
  expect(sent.some(s => s.startsWith('/think/now') && s.includes('platformio.ini'))).toBe(true)
})
