import { expect, mock, test } from 'claude-code/testing'

test('/lupin off quits the helper and silences typing; /lupin on brings it back', async ($, on) => {
  mock.store(on)
  const sent: string[] = []
  on('http.fetch', async (_$, e) => {
    sent.push(e.url.replace('http://127.0.0.1:47391', ''))
    return { value: { status: 200, ok: true, headers: {}, text: 'ok' } } as never
  })
  on('prompt.edit', (_$, e) => ({ text: e.text + e.inputText, cursor: e.cursor + 1 }))
  const edit = () => $.prompt.edit({ origin: { kind: 'composer' }, text: '', cursor: 0, start: 0, end: 0, inputText: 'a' } as never)

  const off = await $.command.run({ command: 'lupin', args: 'off' })
  expect(off.text).toContain('オフ')
  expect(sent).toContain('/quit')
  sent.length = 0
  await edit()
  expect(sent).toEqual([])

  await $.command.run({ command: 'lupin', args: 'on' })
  await edit()
  await new Promise(r => setTimeout(r, 0))
  expect(sent).toContain('/char')
})
