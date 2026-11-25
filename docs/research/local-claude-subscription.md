# Driving page interaction from a local Claude subscription

Research for [issue #5](https://github.com/mshafir/coracle/issues/5). Sources fetched 2026-11-25. Every quote below was copied from the page named at that date; policy here has changed several times in 2026, so re-check the two policy pages before building.

## Short answer

- **Permitted route:** Coracle launches the person's own, unmodified, already-installed Claude Code (`claude -p`, non-interactive mode) as a child process. The person signs in to Claude Code themselves through Anthropic's own login. Coracle never sees, stores or sends a credential.
- **Not permitted:** Coracle offering "Sign in with Claude", running its own OAuth flow, reading the token Claude Code stored, or calling the Anthropic API itself with a subscription token.
- **Page tools:** Coracle hosts a local MCP server (read page, click, type, navigate, screenshot) and hands it to that Claude Code process with `--mcp-config`. This is the same shape Anthropic uses for Claude in Chrome and for computer use inside Claude Code.
- **Fallback that is unambiguously allowed:** an Anthropic API key the person supplies, using the Messages API `browser_toolset_20260801` tool. Max and Ultra plans now include monthly API credits that pay for this.
- **Main open uncertainty:** Anthropic's text explicitly protects "an end user signing in to the unmodified Claude Code binary with their own Claude subscription", but the section about products that run Claude Code is written for commercial platforms and asks for the Commercial Terms. Whether a no-backend open-source desktop app needs to do anything under that section is not stated. See [Open questions](#open-questions).

## 1. The current policy, quoted

### 1.1 Claude Code "Legal and compliance" page (the controlling text)

Source: <https://code.claude.com/docs/en/legal-and-compliance> (section "Authentication and credential use").

> **OAuth authentication** is intended exclusively for purchasers of Claude Free, Pro, Max, Ultra, Team, and Enterprise subscription plans and is designed to support ordinary use of Claude Code and other native Anthropic applications.

> **Developers** building products or services that interact with Claude's capabilities, including those using the Agent SDK, should use API key authentication through Claude Console or a supported cloud provider. Anthropic does not permit third-party developers to offer Claude.ai login into their own applications, or to route requests through Free, Pro, Max, or Ultra plan credentials on behalf of their users. Moreover, developers may not collect, store, or intermediate Claude.ai credentials or session tokens — sign-in to a Claude account must complete through Anthropic's own flow.

> This does not restrict how customers provision and manage their own API keys [...] Nor does it prevent an end user from signing in to the unmodified Claude Code binary with their own Claude subscription, including where a platform hosts Claude Code as described under *Can customers offer Claude Code in their products?* above.

> Anthropic reserves the right to take measures to enforce these restrictions and may do so without prior notice.

Same page, section "Can customers offer Claude Code in their products?":

> Unless we've mutually agreed otherwise, preinstalling or running Claude Code in your products or services (e.g. in hosted sandboxes or other agent infrastructure) requires agreeing to our Commercial Terms of Service and complying with the conditions below:
>
> - **The Claude Code binary must not be modified.** Claude Code must be installed and run as published by Anthropic, and customers may not remove, disable, or restrict any authentication method built into it (including methods that permit signing in with a Claude account or the user's own API key).
> - **Customers may not pay for, resell, or intermediate Claude usage on their end users' behalf.** Each end user must authenticate with their own Anthropic API key, Claude subscription plan credentials, or 3P inference provider credential [...]. That usage is billed directly to the end user under their own agreement with Anthropic [...]

And on naming:

> You can accurately say, in plain text, that your product has Claude Code preinstalled or that it runs Claude Code. But you can't use the Claude Code or Anthropic names or logos as part of your own product, feature, or company name, in your own logo, or in a way that suggests Anthropic built, endorses, or is partnered with your product.

Same page, "Acceptable use":

> Advertised usage limits for Pro, Max, and Ultra plans assume ordinary, individual usage of Claude Code and the Agent SDK.

### 1.2 Agent SDK docs

Source: <https://code.claude.com/docs/en/agent-sdk/overview> and <https://code.claude.com/docs/en/agent-sdk/quickstart> (same note on both).

> Unless previously approved, Anthropic does not allow third party developers to offer claude.ai login or rate limits for their products, including agents built on the Claude Agent SDK. Use the API key authentication methods described in the Quickstart instead.

The SDK quickstart documents only API-key and cloud-provider authentication. The SDK overview also says a product built on it "should maintain its own branding and not appear to be Claude Code or any Anthropic product."

### 1.3 Subscription usage for `claude -p` and the Agent SDK

Source: <https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan>. The whole article is currently two notices:

> **Update October 7, 2026:** Claude Max, Ultra, and Team plans now include monthly API credits. They cover the Claude API, Claude Managed Agents, and the Claude Agent SDK and `claude -p` when you run them with an API key from your linked Claude Console organization. Nothing changes for your plan: when you're signed in with your Claude plan, the Claude Agent SDK and `claude -p` still draw from your subscription limits.

> **Update June 15, 2026:** We've paused the previously-announced changes to Claude Agent SDK usage. For now, nothing has changed: Claude Agent SDK, `claude -p`, and third-party app usage still draw from your subscription limits.

So today a signed-in `claude -p` run is paid for by the person's plan. Note the words "paused" and "for now": Anthropic had announced a change to how this usage is charged and has not withdrawn it. I did not find the original announcement on an Anthropic page; the pause notice is the only first-party trace.

### 1.4 Consumer Terms of Service

Source: <https://www.anthropic.com/legal/consumer-terms> (page shows "Effective Oct 8, 2025"). Section 2:

> You may not share your Account login information, Anthropic API key, or Account credentials with anyone else. You also may not make your Account available to anyone else.

Section 3 lists as prohibited:

> Except when you are accessing our Services via an Anthropic API Key or where we otherwise explicitly permit it, to access the Services through automated or non-human means, whether through a bot, script, or otherwise.

`claude -p` is a documented Anthropic feature for scripted use with a subscription login (see 2.1), which is the "otherwise explicitly permit" case. A third-party client replaying a subscription token against the API is not.

### 1.5 How the wording changed during 2026

From Internet Archive captures of `code.claude.com/docs/en/legal-and-compliance.md`:

| Capture | OAuth wording |
| --- | --- |
| [2026-03-27](https://web.archive.org/web/20260327081821/https://code.claude.com/docs/en/legal-and-compliance.md) | "OAuth authentication (used with Free, Pro, and Max plans) is intended exclusively for Claude Code and Claude.ai. Using OAuth tokens obtained through Claude Free, Pro, or Max accounts in any other product, tool, or service — including the Agent SDK — is not permitted and constitutes a violation of the Consumer Terms of Service." |
| [2026-05-13](https://web.archive.org/web/20260513174345/https://code.claude.com/docs/en/legal-and-compliance.md), [2026-07-04](https://web.archive.org/web/20260704031356/https://code.claude.com/docs/en/legal-and-compliance.md) | Softened to "designed to support ordinary use of Claude Code and other native Anthropic applications". The "including the Agent SDK ... violation" sentence is gone. No section on products that run Claude Code. |
| [2026-10-19](https://web.archive.org/web/20261019065100/https://code.claude.com/docs/en/legal-and-compliance.md) and today | Adds "Can customers offer Claude Code in their products?" and the explicit sentence protecting an end user signing in to the unmodified binary. Adds the ban on collecting, storing or intermediating credentials. |

Direction of travel: the ban on third-party apps handling subscription credentials has only become more explicit, while running the real Claude Code with the person's own login has become explicitly protected. Press coverage of the February 2026 tightening exists (for example [The Register, 2026-02-20](https://www.theregister.com/software/2026/02/20/anthropic-clarifies-ban-on-third-party-tool-access-to-claude/5014546)) but is secondary; I found no Anthropic blog post announcing any of these changes.

## 2. The routes, sorted by what the policy says

### 2.1 Launch the person's installed Claude Code in non-interactive mode — recommended

Source: <https://code.claude.com/docs/en/headless>, <https://code.claude.com/docs/en/cli-reference>, <https://code.claude.com/docs/en/authentication>.

- `claude -p` runs Claude Code without the terminal UI. The docs say: "To drive the same agent loop from a language other than Python or TypeScript, run the CLI as a subprocess with the `-p` flag and `--output-format json`" ([Agent SDK overview](https://code.claude.com/docs/en/agent-sdk/overview)). Coracle will be native Swift/GTK code, so this is the documented route for it.
- It uses whatever credential Claude Code already has. "Subscription OAuth credentials from `/login`" is "the default for Claude Pro, Max, Ultra, Team, and Enterprise users" (authentication page, precedence list). Coracle does nothing about login.
- Coracle can check readiness with `claude auth status`, which prints JSON and "exits with code 0 if logged in, 1 if not"; its `authMethod` field distinguishes `claude.ai` from `api_key`. If the person is not signed in, Coracle tells them to run `claude` and sign in. It must not start or embed the login itself.
- Flags that matter:
  - `--input-format stream-json --output-format stream-json --verbose` for a long-lived, multi-turn session with streamed events.
  - `--mcp-config <file-or-json>` plus `--strict-mcp-config` so the session gets Coracle's page tools and not the person's other MCP servers.
  - `--tools ""` to remove the built-in tools (Bash, file edit) so a page session cannot touch the file system. "The flag doesn't affect MCP tools."
  - `--allowedTools "mcp__coracle__*"` to pre-approve chosen tools, or `--permission-prompt-tool mcp__<server>__<tool>` to route each approval to a tool Coracle hosts, which lets Coracle show its own "Claude wants to click X" prompt.
  - `--append-system-prompt` for browser-specific instructions; `--resume` / `--session-id` to continue a conversation.
- Do **not** pass `--bare`: "bare mode doesn't use your subscription login" and "never reads OAuth credentials or the system keychain."
- An environment variable trap: "If you have an active Claude subscription but also have `ANTHROPIC_API_KEY` set in your environment, Claude Code uses the API key once you approve it." Coracle should show which credential is active (from `claude auth status`) so nobody is billed by surprise.

Why this fits the policy: the binary is unmodified, the person authenticated to it through Anthropic's flow, usage is billed to them, and Coracle neither offers Claude login nor touches a token. That matches both conditions in 1.1 and the "Nor does it prevent an end user..." sentence.

### 2.2 The Agent SDK with subscription login — works, but the docs tell developers not to ship it

Source: <https://code.claude.com/docs/en/agent-sdk/hosting>, <https://code.claude.com/docs/en/agent-sdk/quickstart>.

The SDK is a wrapper around the same program: "When your code calls `query()`, the SDK spawns a separate `claude` CLI process and talks to it over stdio." Both SDKs "bundle a native Claude Code binary". Because it is the same binary, it picks up a stored subscription login, and the support article in 1.3 confirms such usage "still draw[s] from your subscription limits".

But the SDK docs' instruction to developers is the note in 1.2: use API keys, do not offer claude.ai login or rate limits in your product. For Coracle the SDK also adds little: it is Python/TypeScript only, and it would mean shipping a second, Coracle-bundled copy of Claude Code rather than using the one the person installed and signed in to. Route 2.1 gets the same agent loop without the ambiguity.

### 2.3 Taking the subscription token and calling the API directly — prohibited

This is exactly what the policy names: developers may not "offer Claude.ai login into their own applications", "route requests through Free, Pro, Max, or Ultra plan credentials on behalf of their users", or "collect, store, or intermediate Claude.ai credentials or session tokens". That covers running an OAuth flow in Coracle, reading Claude Code's stored credential from the keychain or its config directory, and asking the person to paste a `claude setup-token` token into Coracle so Coracle can call the API. Anthropic says it may enforce this "without prior notice".

A narrower case: `claude setup-token` creates a one-year token meant to be set as `CLAUDE_CODE_OAUTH_TOKEN` "for CI pipelines and scripts where browser login isn't available" ([authentication](https://code.claude.com/docs/en/authentication#generate-a-long-lived-token)). Even passing that to Claude Code would require Coracle to store a Claude credential, which the policy forbids developers from doing. Coracle has no need for it: the person's normal login already works.

### 2.4 Bring your own API key — allowed, and now partly covered by plans

Source: <https://platform.claude.com/docs/en/agents-and-tools/tool-use/browser-use-tool>, <https://platform.claude.com/docs/en/about-claude/api-credits-for-subscribers>.

- The Messages API has a first-party **browser use tool**: "an Anthropic-defined client toolset: one `browser_toolset_20260801` entry in `tools` gives Claude 27 member tools by default, such as `navigate`, `read_page`, `left_click`, and `screenshot`". It "lets Claude navigate, read, and interact with webpages in a browser that your application runs." It is a client-side tool: Coracle would execute each action and return results; "Anthropic does not run browser actions".
- This needs an API key, which is not "your existing subscription". However, Max ($100/month), Ultra ($200/month) and Team plans now include monthly API credits that cover "Claude API, Claude Managed Agents, the Claude Agent SDK, and playground". Pro is not eligible. The person must link a Console organization and create a key.
- Storing a person's own API key locally is expressly fine: the policy "does not restrict how customers provision and manage their own API keys".

This is a sound second mode ("use an API key instead"), and it works with no Claude Code install. It is not the bring-your-subscription experience for Pro users.

## 3. Exposing page tools to Claude

### 3.1 Mechanism: a local MCP server that Coracle hosts

Source: <https://code.claude.com/docs/en/agent-sdk/mcp>, <https://code.claude.com/docs/en/agent-sdk/custom-tools>, <https://code.claude.com/docs/en/cli-reference>.

- Claude Code accepts MCP servers as stdio processes ("Local processes that communicate via stdin/stdout. Use this for MCP servers you run on the same machine") or over HTTP (`"type": "http"` with a `url` and optional `headers`).
- Two workable layouts:
  1. Coracle listens on a loopback HTTP port and passes `{"type":"http","url":"http://127.0.0.1:<port>/mcp","headers":{"Authorization":"Bearer <per-session secret>"}}` in `--mcp-config`. The header matters: any local process can reach a loopback port, and these tools act inside the person's logged-in pages.
  2. A tiny stdio helper binary shipped with Coracle that Claude Code launches and that talks back to the running browser over a Unix socket. No open port. This mirrors what Claude in Chrome does (3.2).
- Tools appear to Claude as `mcp__<server-name>__<tool-name>`.
- Screenshots can be returned: MCP tool results accept image blocks, "encoded as base64 ... A PNG, JPEG, GIF, or WebP image reaches Claude as visual input."
- Large text results are cut off: "When a successful tool result with no image content is larger than 25,000 tokens, Claude Code saves the output to a file and replaces the tool result with an error message that names the file path". With built-in file tools disabled, Claude could not read that file, so the read-page tool must page or filter its own output.
- With `-p`, "Claude Code waits for still-pending servers to connect before running the first turn, up to the `MCP_TIMEOUT` startup timeout, 30 seconds by default", so Coracle's server must be listening before it launches Claude.

### 3.2 How Anthropic structures its own browser integrations

**Claude in Chrome driven from Claude Code.** Source: <https://code.claude.com/docs/en/chrome>.

- It is exposed inside Claude Code as an MCP server named `claude-in-chrome` ("Run `/mcp`, select `claude-in-chrome`, then select **View tools**").
- The link between the CLI and the browser is Chrome native messaging: "The first time you enable Chrome integration, Claude Code installs a native messaging host configuration file" (`com.anthropic.claude_code_browser_extension.json`). The docs also list a network dependency on `bridge.claudeusercontent.com`.
- It acts in the person's real browser profile: "shares your browser's login state". "When Claude encounters a login page or CAPTCHA, it pauses and asks you to handle it manually."
- Permissions are per site, with an option "to allow all actions on that site for the session".
- It needs a real `/login`: "If you authenticate with an API key or a long-lived token from `claude setup-token`, Claude Code keeps Chrome integration off".
- The docs warn that leaving it always on "increases context usage since the browser tools and their instructions are always loaded".

**Claude in Chrome side panel.** Source: <https://support.claude.com/en/articles/12012173-getting-started-with-claude-in-chrome>. "Claude sees what's on the page and can act on it, reading, clicking, typing, navigating, and filling forms". It is on paid plans only, and "the side panel runs as a Claude Cowork session" that lives with the account in the cloud. That is Anthropic's own product on Anthropic's own login; it is not a pattern a third party may copy with subscription credentials.

**Computer use in Claude Code.** Source: <https://code.claude.com/docs/en/computer-use>. "Computer use is available as a built-in MCP server called `computer-use`", macOS only, approved per app per session, and "not available in non-interactive mode with the `-p` flag". It is also the slowest option by Anthropic's own ranking: MCP server first, then Bash, then Claude in Chrome, and only then computer use.

**Computer use and browser use on the API.** Sources: <https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool>, <https://platform.claude.com/docs/en/agents-and-tools/tool-use/browser-use-tool>. Both are client toolsets: Claude returns `tool_use` blocks and the application performs them and returns `tool_result` blocks. The browser toolset is the better model for Coracle's tool design. Its members include `navigate`, `screenshot`, `zoom`, `read_page` (accessibility tree as text with each element tagged `[ref_N]`), `find`, `get_page_text`, `left_click` / `hover` / `scroll` (targeting either a `ref` or viewport coordinates), `type`, `key`, `form_input`, and tab management. `javascript_exec`, `read_console`, `read_network` and `file_upload` are "disabled by default".

Lessons to carry into Coracle's tool surface:

- Offer both structure and pixels. Element references from a page read let Claude click without locating things in a screenshot; screenshots and coordinates cover canvas-style pages.
- Keep script execution, console, network and file upload off unless the person turns them on.
- Treat page content as untrusted. Anthropic says of its API tool that "classifiers automatically scan what the tool returns, such as screenshots, to flag potential prompt injections"; that protection is described for the API tools, and I found no statement that it applies to results from a third-party MCP server in Claude Code. Coracle should plan on per-site approval and confirmation for consequential actions rather than rely on it.
- Stop for the person at login pages and CAPTCHAs.

## 4. Recommended shape for Coracle

1. A **Claude session** on a tab starts a child process: the person's own `claude`, with `-p`, stream-json in and out, `--strict-mcp-config`, `--mcp-config` pointing at Coracle's page-tool server scoped to that tab, built-in tools disabled, and Coracle's approval tool as `--permission-prompt-tool`.
2. Coracle detects Claude Code on `PATH` and runs `claude auth status`. Not installed or not signed in means a plain message with Anthropic's install and sign-in instructions. No login UI in Coracle.
3. Coracle stores no Anthropic credential of any kind in this mode.
4. Describe it accurately: "runs Claude Code", in plain text, without Anthropic's logos or a feature name built on "Claude Code".
5. Optional second mode: the person's own API key with the API browser toolset.
6. Keep the Claude layer behind a small interface. The charging rules for `claude -p` were nearly changed in 2026 and are only "paused".

## Open questions

- **Does a free, no-backend, open-source app need the Commercial Terms?** The hosted-products section says "preinstalling or running Claude Code in your products or services ... requires agreeing to our Commercial Terms of Service". Its examples are hosted sandboxes and agent infrastructure. Coracle would meet both listed conditions, and the end-user sentence protects the person, but the text does not say what, if anything, a project like Coracle itself must agree to. The page directs such questions to Anthropic sales. Worth asking before release.
- **Will `claude -p` keep drawing from plan limits?** The June 15, 2026 notice says changes are "paused ... for now". Unknown when or whether they return.
- **"Ordinary, individual usage".** Limits assume it. A person driving one tab interactively seems to fit; unattended, scheduled or many-tab automation may not. Anthropic does not define the boundary.
- **Not verified by running anything.** All flag behaviour above is from the docs; none of it was tested here. In particular, untested: `--tools ""` together with `--permission-prompt-tool`, image results from an HTTP MCP server in `-p` mode, and startup latency of a non-bare `claude -p` session.
- **Not read:** the Commercial Terms of Service and the Usage Policy text itself (only the pages that reference them).
- **Consumer Terms date.** The page fetched today shows "Effective Oct 8, 2025". I could not confirm whether a newer version is pending.
