// Excuses for what the session is doing right now, one per tool call.

const clip = (s: string, n = 18) => (s.length > n ? `${s.slice(0, n)}…` : s)
const base = (path: string) => path.split('/').filter(Boolean).pop() ?? path
const pick = <T>(xs: readonly T[]): T => xs[Math.floor(Math.random() * xs.length)]!

/** What the call is about, in a few words: the command, file, pattern or query. */
export function subjectOf(tool: string, input: Record<string, unknown>): string {
  const str = (k: string) => (typeof input[k] === 'string' ? (input[k] as string) : undefined)
  const firstWord = (cmd: string) => cmd.trim().split(/\s+/).slice(0, 2).join(' ')
  switch (tool) {
    case 'Bash': return clip(firstWord(str('command') ?? ''))
    case 'Read': case 'Edit': case 'Write': case 'NotebookEdit':
      return clip(base(str('file_path') ?? str('notebook_path') ?? ''))
    case 'Grep': case 'Glob': return clip(str('pattern') ?? '')
    case 'WebSearch': return clip(str('query') ?? '')
    case 'WebFetch': return clip((str('url') ?? '').replace(/^https?:\/\//, ''))
    case 'Agent': return clip(str('description') ?? '')
    case 'Skill': return clip(str('skill') ?? '')
    default: return ''
  }
}

const TEMPLATES: Record<string, readonly ((s: string) => string)[]> = {
  Bash: [s => `「${s}」が言うことを聞きませんで`, s => `${s} の機嫌を伺っております`, s => `ターミナルで ${s} と格闘中です`],
  Read: [s => `${s} を熟読しております`, s => `${s} の行間を読んでおります`],
  Edit: [s => `${s} に赤ペンを入れております`, s => `${s} を慎重に手術中です`],
  Write: [s => `${s} を一筆したためております`, s => `${s} を清書しております`],
  NotebookEdit: [s => `${s} のノートを書き直しております`],
  Grep: [s => `「${s}」を草の根分けて探しております`, s => `「${s}」の聞き込み中です`],
  Glob: [s => `${s} に合うファイルを点呼中です`],
  WebSearch: [s => `「${s}」でネットの海を泳いでおります`, s => `「${s}」を世界中に聞き回っております`],
  WebFetch: [s => `${s} まで出張しております`],
  Agent: [s => `応援を呼んでおります（${s}）`, () => `部下に仕事を振っております`],
  Skill: [s => `${s} の巻物を広げております`],
}
const FALLBACK: readonly ((tool: string) => string)[] = [
  t => `${t} の扱いに手間取っております`,
  t => `${t} を説得しております`,
]

/** An instant excuse built from the tool and its subject. */
export function templateExcuse(tool: string, subject: string): string {
  const forTool = TEMPLATES[tool]
  if (forTool !== undefined && subject !== '') return pick(forTool)(subject)
  return pick(FALLBACK)(tool)
}

export const liveExcusePrompt = (tool: string, subject: string, request: string) =>
  `アシスタントが作業中で、返事を待たせています。今まさにしている作業についての、ユーモアのある日本語の言い訳を1つだけ書いてください。
25文字以内、言い訳の文だけ、記号や引用符なし。

ユーザーの依頼: ${request.slice(0, 200)}
今の作業: ${tool}${subject ? `（${subject}）` : ''}`
