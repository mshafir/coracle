# Launching Claude Code with the AI session's restrictions

Research for [Launching Claude Code with the AI session's restrictions](https://github.com/mshafir/coracle/issues/21). It checks the decision in [AI session: providers, permissions and reach](https://github.com/mshafir/coracle/issues/14) and builds on [Driving page interaction from a local Claude subscription](https://github.com/mshafir/coracle/blob/research/local-claude-subscription/docs/research/local-claude-subscription.md), which is not repeated here.

Sources fetched 2026-11-25. Local checks ran against Claude Code 2.1.332 on macOS, signed in with a claude.ai subscription.

Each claim is marked:

- **Documented**: stated in Anthropic's Claude Code or Agent SDK documentation, quoted and linked.
- **Observed**: seen on this machine. See [What was run locally](#what-was-run-locally).
- **Inferred**: my reading of the two above; not stated and not tested.

## Short answer

All six properties can be met with the person's installed, unmodified Claude Code. None forces the decision back open. Two caveats narrow it:

1. **Plugin-provided MCP servers are lost.** Ignoring the person's settings files also switches off their plugins, and with them any MCP server a plugin supplies. Servers they added with `claude mcp add` at user scope and their claude.ai connectors still load.
2. **The best permission channel is not a documented command-line interface.** Routing every permission request to Coracle over the process's own input and output works, and it is what Anthropic's Agent SDK does, but Anthropic documents it only through the SDK's types. The documented alternative for other languages (an MCP "prompt tool") works for everything except tools that a server marks as needing a person.

One stated plan threatens the whole route: Anthropic says `--bare` "will become the default for `-p` in a future release", and bare mode does not use the subscription login. See [Stated plans](#stated-plans-and-terms).

### The launch, in one place

```sh
cd <an empty directory Coracle owns>   # not a code project
claude -p \
  --input-format stream-json --output-format stream-json --verbose \
  --tools "" \
  --setting-sources "" \
  --permission-mode default \
  --mcp-config '{"mcpServers":{"coracle":{…}}}' \
  --permission-prompt-tool stdio \
  --append-system-prompt-file <Coracle's instructions> \
  --session-id <uuid Coracle chose>        # later: --resume <that uuid>
```

with `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` in the child's environment. Do not pass `--strict-mcp-config` (it would drop the person's servers and connectors) and do not pass `--bare` (no subscription login).

## 1. Shell, file and web tools off

**Verdict: can. Documented and observed.**

- `--tools ""` removes every built-in tool. **Documented** ([CLI reference](https://code.claude.com/docs/en/cli-reference)):
  > Restrict which built-in tools Claude can use. Use `""` to disable all, `"default"` for the default set, or tool names like `"Bash,Edit,Read"`. […] The flag doesn't affect MCP tools; to deny those too, use `--disallowedTools "mcp__*"`.
- That covers Bash, the file tools, WebFetch and WebSearch, which are all built-in tools ([tools reference](https://code.claude.com/docs/en/tools-reference)). **Inferred** from the same list: it also removes the Agent (subagent) and Skill tools, so subagents and skills cannot be used to get round it.
- **Observed**: with `--tools ""` and a stub page-tools server, the session's tool list was exactly `mcp__coracle__read_page` and `mcp__coracle__run_script`. With no MCP server at all the tool list was empty.
- `--restricted` is not enough on its own. **Documented**: it "removes the built-in tools that run commands or code, and WebFetch", but it keeps the file tools (confined to the working directory) and does not mention WebSearch. It can be added as a second layer; see property 3.
- Carried over from the earlier research: a text tool result over 25,000 tokens is saved to a file that Claude then cannot read without file tools, so Coracle's read-page tool must page its own output.

## 2. Coracle's page tools alongside the person's own servers and connectors

**Verdict: can. Documented and observed.**

- `--mcp-config <file-or-json>` adds servers. Leaving out `--strict-mcp-config` keeps everything else. **Documented** ([CLI reference](https://code.claude.com/docs/en/cli-reference)): `--strict-mcp-config` is what makes Claude Code "skip the MCP servers configured in places such as `.mcp.json`, `~/.claude.json`, or a plugin".
- Claude.ai connectors arrive by themselves. **Documented** ([MCP](https://code.claude.com/docs/en/mcp#use-mcp-servers-from-claude-ai)): "If you've logged into Claude Code with a claude.ai account, MCP servers you've added in claude.ai, known as connectors, are automatically available in Claude Code". They are "fetched only when your active authentication method is a claude.ai subscription login", so a person running Claude Code on an API key gets none.
- **Observed**: a session started with `--mcp-config` for a `coracle` server listed that server and the account's three claude.ai connectors (two connected with 24 tools between them, one needing sign-in).
- With `-p` and `--mcp-config`, Claude Code "waits for still-pending servers to connect before running the first turn, up to the `MCP_TIMEOUT` startup timeout, 30 seconds by default" (**documented**), so Coracle's server must be up first.

Things to design around:

- **The working directory matters.** Local-scope servers are stored in `~/.claude.json` "under that project's path" and project-scope servers come from `.mcp.json` in the directory Claude Code starts in ([MCP scopes](https://code.claude.com/docs/en/mcp#mcp-installation-scopes)). **Documented**: in `-p` runs Claude Code "loads project-scoped servers without asking". Coracle should launch in an empty directory of its own. The person then gets their **user-scope** servers and connectors, not servers tied to one of their code projects. **Inferred**: that is the right reading of "the person's own tools" for a browser.
- **Servers that need a fresh sign-in cannot be fixed from inside the session.** Interactive commands such as `/login` are unavailable in `-p` (**documented**, [headless](https://code.claude.com/docs/en/headless)). A connector showing "needs sign-in" stays that way until the person fixes it in Claude Code or on claude.ai.
- **Name clash.** If the person already has a server called `coracle`, precedence rules pick one definition by name. Use a distinctive name. **Inferred.**

## 3. The person's allow-lists and settings not honoured, their servers and connectors still loaded

**Verdict: can, with one loss. The two are stored separately, so they separate. Documented and observed.**

Why it works: permission rules, hooks and the plugin list live in settings files (`~/.claude/settings.json`, `.claude/settings.json`, `.claude/settings.local.json`). User-scope and local-scope MCP servers live in a different file, `~/.claude.json`, and connectors come from the account.

- `--setting-sources ""` loads none of the three settings files. **Documented** for the flag ([CLI reference](https://code.claude.com/docs/en/cli-reference)): "Comma-separated list of setting sources to load (`user`, `project`, `local`)". The empty value is **documented** for the SDK option that maps to it ([Use Claude Code features in the SDK](https://code.claude.com/docs/en/agent-sdk/claude-code-features)): "pass an empty array to disable user, project, and local settings". **Observed**: the command line accepts `--setting-sources ""`.
- What survives it. **Documented**, same page, "What settingSources does not control":
  > | `~/.claude.json` global config | Always read |
  >
  > | claude.ai MCP connectors | Loaded when the session authenticates with your claude.ai login. […] |

  The same table lists managed policy settings and auto memory as also read regardless.
- **Observed**, comparing a default launch with `--setting-sources ""`:
  - the person's two `SessionStart` hooks ran by default and did not run with the flag;
  - a plugin-provided MCP server was present by default and absent with the flag;
  - all three claude.ai connectors were present both times;
  - the subscription login still worked (a live turn completed);
  - available commands and skills dropped from 105 to 60.
- `--restricted` gives the same result by another route. **Documented**: it "loads only managed settings and `--settings`", "refuses `bypassPermissions`", and the help text adds "add `--strict-mcp-config` to skip MCP servers too", which confirms MCP servers otherwise still load. It "requires Claude Code v2.1.248 or later" and is described for "an evaluation harness [that] drives `claude` on a shared machine". **Observed**: same server list as `--setting-sources ""`. Either flag works; `--setting-sources ""` is the older and more plainly documented one, and `--restricted` can be added on top.

What does **not** separate:

- **Plugin-provided MCP servers go with the settings.** Plugins are switched on by the `enabledPlugins` key in settings files, so dropping the settings drops the plugins and their servers (**observed**). Coracle could read the person's `enabledPlugins` and pass it back through `--settings`, but that would also bring back the plugins' hooks and any permission-deciding code they carry. **Inferred**, untested, and I would not do it.
- **Organisation-managed settings always apply**, including any allow rules an employer set. **Documented**: "Managed policy settings and the global `~/.claude.json` config are read regardless of this option." Coracle cannot and should not override these. The effect is that on a managed machine some tool calls may be approved by the organisation's rules before Coracle is asked.
- **A person who signs in through settings loses that.** If their credential comes from an `apiKeyHelper` or an `env` block in `settings.json`, ignoring the file ignores the credential. **Inferred.** Their `model` setting is ignored too, which matches the decision to use Claude Code's default model.
- **`~/.claude.json` is not fully specified.** The docs say it is always read but do not list every key. I found no documented permission allow-list stored there, and the documented place for saved "don't ask again" rules is `.claude/settings.local.json` ([permissions](https://code.claude.com/docs/en/permissions)), which the flag excludes. This machine had no user-scope MCP servers, so "user-scope servers still load" is **documented but not observed**; only connectors were observed surviving.

## 4. Every permission request routed to Coracle

**Verdict: can. Two channels: one fully documented with a gap, one observed working and documented only through the SDK.**

### When Claude Code asks at all

**Documented** ([Configure permissions](https://code.claude.com/docs/en/agent-sdk/permissions)): each tool call is checked in order by hooks, deny rules, ask rules, the permission mode, allow rules, and only then the host application.

> **Auto-approved tools never reach `canUseTool`.** A tool call approved at any earlier step, by `acceptEdits` or `bypassPermissions`, or by an allow rule, skips your `canUseTool` callback

So routing everything to Coracle depends on property 3 (no allow rules, no hooks) plus an explicit `--permission-mode default`. With those in place: "MCP tools require explicit permission before Claude can use them" ([SDK MCP page](https://code.claude.com/docs/en/agent-sdk/mcp)), and with no built-in tools every call is an MCP call. **Observed**: both calls to the stub server, including the read-only one, produced a permission request.

Coracle then applies the decided policy itself, in its own code:

- **Reading and screenshots never ask**: answer "allow" without showing anything. (Or list those tools in `--allowedTools` to skip the round trip. Scope such an entry to exact tool names: a bare tool name approves every call to it.)
- **The person's own tools, once per tool per session**: Coracle remembers its own answers per tool name and replies without asking again. Do not use Claude Code's "remember" feature (`updatedPermissions`), which can write rules into the person's settings files.
- **Run script, submit form, every call**: Coracle shows the prompt every time. The request carries the tool name and the full input (**observed**), so the script text or form contents can be shown.
- **Waiting with no timeout**: **documented**, "permission prompts don't time out" ([TypeScript SDK reference](https://code.claude.com/docs/en/agent-sdk/typescript)).
- A denial can carry a message, which Claude receives as the tool result (**observed**).

Because Coracle also runs the page tools, the hard stops should be enforced a second time inside the page-tools server. That check does not depend on Claude Code's permission system at all. **Inferred**, a design point.

### Channel A: an MCP prompt tool (documented)

`--permission-prompt-tool mcp__coracle__approve`. **Documented** ([CLI reference](https://code.claude.com/docs/en/cli-reference)): "Specify an MCP tool to handle permission prompts in non-interactive mode." The reply format is **documented** ([error reference](https://code.claude.com/docs/en/errors#permission-prompt-tool-returned-an-invalid-result)):

> Return one text block whose text is `{"behavior": "allow"}` or `{"behavior": "deny", "message": "<reason>"}`. To change the input, add `updatedInput` to the `allow` object.

The gap, **documented** ([MCP](https://code.claude.com/docs/en/mcp#require-approval-for-a-specific-tool)): for a tool whose server marks it `anthropic/requiresUserInteraction`,

> an `allow` result from the prompt tool for a flagged tool is converted to a deny with the message `MCP tool requires user interaction; not supported via --permission-prompt-tool`. The Agent SDK's `canUseTool` callback does receive these calls and can approve them

So under Channel A, any of the person's own tools carrying that mark can never run inside Coracle. The docs I read do not spell out the arguments the prompt tool receives; I did not test this channel.

### Channel B: control messages on the process's own input and output (observed)

This is how the Agent SDK's `canUseTool` works. **Documented** ([Agent SDK hosting](https://code.claude.com/docs/en/agent-sdk/hosting)): "the SDK spawns a separate `claude` CLI process and talks to it over stdio." The SDK reference describes permission requests as `control_request` messages with the shape `{ type: "control_request", request_id, request }`, answered by a `control_response`.

**Observed** with `--permission-prompt-tool stdio`:

- Claude Code wrote this line to standard output and waited:
  ```json
  {"type":"control_request","request_id":"…","request":{"subtype":"can_use_tool","tool_name":"mcp__coracle__run_script","mcp_server":{"name":"coracle","source":"dynamic"},"display_name":"Run Script","input":{"code":"1+1"},"permission_suggestions":[…],"tool_use_id":"toolu_…"}}
  ```
- Writing this line to standard input let the call run:
  ```json
  {"type":"control_response","response":{"subtype":"success","request_id":"…","response":{"behavior":"allow","updatedInput":{…}}}}
  ```
- Replying `{"behavior":"deny","message":"The person declined this script."}` blocked the call and Claude reported the refusal.

This channel has no gap for tools marked as needing a person, and needs no extra tool on Coracle's server. But the value `stdio` for `--permission-prompt-tool` is **not in the CLI reference or `--help`**, and the message format is documented only as Agent SDK types. Anthropic's stated advice for other languages is narrower: "To drive the same agent loop from a language other than Python or TypeScript, run the CLI as a subprocess with the `-p` flag and `--output-format json`" ([Agent SDK overview](https://code.claude.com/docs/en/agent-sdk/overview)). Treat Channel B as an interface that can change between versions. The session's first `system/init` event carries a `capabilities` list that the docs say to use "to feature-detect instead of comparing version strings".

**Recommendation:** build on Channel B, keep the approval logic behind one small interface, and keep Channel A as the fallback, since both end in the same Coracle decision code.

### What can still decide before Coracle

- **Organisation-managed** allow rules and hooks (see property 3).
- **Organisation "ask" settings on connector tools**: these always come to the host, "even when an allow rule matches" (**documented**), which suits Coracle.
- **Mods** (plugin code that can approve calls): **documented** as able to "skip your `--permission-prompt-tool` or `canUseTool` callback" on unmanaged setups. They come from plugins, which do not load without the person's settings. **Observed**: with `--setting-sources ""` only four built-in plugins loaded, none user-installed.

## 5. Long-lived streaming sessions, several at once, pausable, stoppable, resumable

**Verdict: can. Flags documented; the message format for follow-ups documented only through the SDK; observed working.**

- **Streaming, multi-turn**: `-p --input-format stream-json --output-format stream-json --verbose`. **Documented** ([CLI reference](https://code.claude.com/docs/en/cli-reference)): `stream-json` input is "realtime streaming input"; "every message must be one newline-terminated JSON line" ([error reference](https://code.claude.com/docs/en/errors)). Add `--include-partial-messages` for text as it is generated. **Observed**: a second message written to standard input after the first `result` event started a second turn in the same process. The line used was `{"type":"user","message":{"role":"user","content":"…"},"parent_tool_use_id":null,"session_id":"…"}`, the SDK's `SDKUserMessage` shape.
- **Several at once**: **documented** ([hosting](https://code.claude.com/docs/en/agent-sdk/hosting)): "One agent session maps to one subprocess. Running N concurrent sessions takes N subprocesses, each with its own process tree and transcript file." Memory per process was not measured.
- **Stop**: **documented** ([headless](https://code.claude.com/docs/en/headless#stop-a-run-with-sigterm)): on SIGTERM Claude Code "exits with code 143" and "leaves the turn that was in progress unfinished"; "To end the turn instead, send SIGINT, or call the Agent SDK's `interrupt()`, before you stop the process."
- **Pause**: there is no freeze-and-thaw. Two things serve:
  - An interrupt ends the current turn and leaves the session open for the next message. **Observed**: writing `{"type":"control_request","request_id":"…","request":{"subtype":"interrupt"}}` cancelled a pending permission request, returned a success response, and ended the turn with an error-type `result`; the process stayed alive. The SDK's `interrupt()` is **documented**; the raw line is not.
  - A session waiting on a permission answer or the next message is already paused at no cost, since prompts do not time out.
  
  **Inferred**: "pause" in Coracle is "interrupt, then continue with a follow-up message when the person resumes". Claude does not pick up mid-sentence.
- **Resume after Coracle restarts**: **documented**. `--session-id <uuid>` sets the id at start; `--resume <id>` continues it, and "Claude Code finds the session by its ID in any project on this machine". Transcripts are stored "under `~/.claude/projects/<encoded-cwd>/*.jsonl`" ([SDK sessions](https://code.claude.com/docs/en/agent-sdk/sessions)). **Observed**: a new process started with `--resume` recalled the previous turn. Pass the same restriction flags again on every resume; they are launch flags, not saved with the session.
  - After a kill, "Claude Code leaves the interrupted turn as it is, and your next prompt drives the conversation"; set `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1` to continue it instead. A permission prompt that was open at a SIGTERM is left unanswered (**documented**).

Design consequences:

- **The transcript belongs to Claude Code, not Coracle.** It sits in the person's Claude Code folder. Coracle should keep its own copy of the conversation (from the output stream) for display and for the archive, and treat Claude Code's file as what makes continuing possible. I did not check how long Claude Code keeps transcripts or whether these sessions show in the person's own `claude --resume` list.
- **A dead child is normal.** Resuming is cheap, so Coracle can let idle sessions' processes exit and restart them with `--resume` on the next message.

## 6. System prompt, and what else of the person's setup loads

**Verdict: can. Documented; the loading behaviour also observed.**

- **Instructions**: `--append-system-prompt` / `--append-system-prompt-file` add to Claude Code's default prompt; `--system-prompt` / `--system-prompt-file` replace it (**documented**, [CLI reference](https://code.claude.com/docs/en/cli-reference#system-prompt-flags)). **Observed**: `--append-system-prompt` accepted together with stream-json input.
  - The default prompt is written for coding. Appending is the documented "lowest-risk customization" ([Modifying system prompts](https://code.claude.com/docs/en/agent-sdk/modifying-system-prompts)) and keeps Anthropic's own safety instructions; replacing gives a cleaner browser persona but removes them. **Inferred**: start with append.
  - **Documented**: the prompt is built "once, on a conversation's first request" and reused on `--resume` "until the conversation is compacted". Changing Coracle's instructions therefore does not reach existing sessions straight away. `--system-prompt-snapshot off` rebuilds it every request.
- **What loads, and the switch for each**:

  | The person's… | Loads by default in `-p`? | With `--setting-sources ""` | Other switch |
  | --- | --- | --- | --- |
  | `CLAUDE.md` and rules files | Yes | No (documented: they load when the matching source is included) | `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` |
  | Skills and custom commands | Yes | Their own: no. Built-in ones remain (observed: 105 → 60) | `--disable-slash-commands`; `--tools ""` removes the Skill tool |
  | Hooks in settings files | Yes | No (observed) | — |
  | Plugins (and their hooks, servers) | Yes | No; four built-in plugins remain (observed) | — |
  | Auto memory | Yes | **Still loads** (documented) | `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` |
  | Organisation-managed settings, hooks, `CLAUDE.md` | Yes | **Still load** (documented) | None available to Coracle |
  | MCP servers in `~/.claude.json`, connectors | Yes | Still load (the point of property 3) | `--strict-mcp-config` |

  **Documented** default ([headless](https://code.claude.com/docs/en/headless)): without `--bare`, "`claude -p` discovers and loads them as an interactive session would, including anything configured in the working directory or `~/.claude`."
- **Granularity**: the three sources are all-or-nothing each. A source's `CLAUDE.md`, skills, hooks and permission rules come or go together. Coracle wants none of them, so this costs nothing.
- `--safe-mode` is the wrong tool: it also disables MCP servers and leaves permissions "work[ing] normally", meaning the person's allow-lists stay.

## Stated plans and terms

Nothing new in Anthropic's terms beyond the earlier research; the "Authentication and credential use" passages on the [legal page](https://code.claude.com/docs/en/legal-and-compliance) read the same today. Three things in the docs bear on this route:

- **`--bare` is to become the default for `-p`.** **Documented** ([headless](https://code.claude.com/docs/en/headless#start-faster-with-bare-mode)):
  > `--bare` is the recommended mode for scripted and SDK calls, and will become the default for `-p` in a future release.

  and, of bare mode: "Claude Code never reads OAuth credentials or the system keychain" and "only servers supplied on the command line connect". Taken literally, a future default `claude -p` would use neither the person's subscription login nor their own MCP servers, which removes both halves of the decision. The docs name no date and no opt-out flag; `--help` on 2.1.332 has none. This is the largest risk to the whole approach and worth asking Anthropic about.
- **Defaults have already shifted once.** **Documented**: "With Claude Code v2.1.302 or later, `claude -p` runs start in Manual mode when nothing sets a permission mode." Coracle should pass every flag it relies on explicitly and never lean on a default.
- **Driving `claude` from a harness is an anticipated use.** The `--restricted` flag is documented for "an evaluation harness [that] drives `claude`". That is not a statement about terms, only that the shape is expected.

Many behaviours above are tied to recent versions (2.1.199, 2.1.248, 2.1.259, 2.1.302). Coracle needs a minimum supported Claude Code version and a check at start-up.

## Open uncertainties

- **Channel B's stability.** `--permission-prompt-tool stdio`, the `control_request` / `control_response` lines and the stream-json user-message line are observed and SDK-documented, not CLI-documented.
- **Channel A untested**, including the exact arguments the prompt tool receives.
- **When and how `--bare` becomes the `-p` default**, and whether a subscription login will remain usable from `-p` afterwards.
- **User-scope MCP servers surviving `--setting-sources ""`** is documented but was not observed (none configured here). Only connectors were observed surviving.
- **Undocumented contents of `~/.claude.json`.** It is always read; I could not rule out some stored approval living there.
- **Managed machines.** Organisation rules can approve or deny before Coracle is asked. Not tested.
- **Transcript retention and visibility** in the person's Claude Code folder.
- **Cost of loading the person's servers.** Every connector's tool descriptions count against context on each session. Not measured.
- **Linux.** Everything observed was on macOS.

## What was run locally

Claude Code 2.1.332, macOS, claude.ai subscription login, in an empty scratch directory. No credential or token file was read.

1. `claude --help` and `claude mcp --help`.
2. Several launches that sent **no prompt**, only `initialize` and `mcp_status` control requests, so no model request was made. Compared: default; `--setting-sources ""`; `--restricted`; `--restricted --tools ""`; `--setting-sources "" --strict-mcp-config`. Read: which hooks fired, command count, and MCP servers by kind (connector, plugin, Coracle stub).
3. One two-turn session on the smallest model with `--tools "" --setting-sources "" --strict-mcp-config --mcp-config <stub> --permission-prompt-tool stdio --append-system-prompt … --session-id …`. The stub server offered `read_page` and `run_script`. The driver allowed the first and denied the second, then sent a follow-up message.
4. One session with `--resume` on that id in a fresh process: a recall question, then an `interrupt` control request during a tool-calling turn.
5. One single-turn session with no MCP server to read the plugin and tool lists.

Reported cost of 3 to 5 together was under one US cent of plan usage.
