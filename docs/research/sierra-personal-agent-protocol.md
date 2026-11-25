# Sierra's personal agent protocol (Personal Agent Protocol, "Poppy")

Research for [issue #19](https://github.com/mshafir/coracle/issues/19). Researched 2026-11-25.
The protocol is seven weeks old and has shipped six versions; anything here can be out of date
within weeks. Spec quotes are from the spec repository at commit
[`589743a`](https://github.com/personal-agent-protocol/personal-agent-protocol/commit/589743afa56ee02bea71d1509c29b0b4ca5b3e50)
(2026-11-18).

## Short answer

- The thing the owner meant exists. Its real name is **Personal Agent Protocol**, nicknamed
  **Poppy**. It is the only candidate found; nothing else from Sierra matches.
- It is an open protocol (Apache 2.0) announced by Sierra and Meta on 2026-10-06 for how a
  person's own AI agent identifies itself to a business, gets the person's permission through
  OAuth, and then works through the business's APIs, website or its own agent.
- Version 1.0 was published in mid-November 2026. It has a long partner list, one large personal
  agent (Meta's Muse) and at least one business observably serving it. It has no foundation, no
  published reference implementation and essentially one spec author.
- Coracle would play the **Personal Agent** role. Two requirements of version 1.0 clash with
  Coracle as planned:
  1. The agent's identity must be a public HTTPS URL with a signing key behind it that should not
     ship inside a distributed app. Coracle has no backend.
  2. The agent must use "a browser it controls ... never the User's own browser". Coracle is the
     user's own browser.
- Both gaps are open topics on the protocol's roadmap ("Self-hosted personal agents"). Neither is
  solved today.
- Poppy does not replace Claude. It is an identity, permission and discovery layer; a model still
  does the work. It does offer a different route from "Claude drives the tab where I am already
  logged in", and the maintainers are inclined to declare that route outside the protocol.
- Suggested position: do not build Poppy into v1, keep the door open (an agent-owned profile is
  the piece that matters), and watch three upstream issues listed at the end.

## What it is

| | |
| --- | --- |
| Name | Personal Agent Protocol, "Poppy" for short |
| Site and spec | <https://personalagentprotocol.org>, spec at `/docs/1.0/spec` |
| Source | <https://github.com/personal-agent-protocol/personal-agent-protocol> |
| License | Apache 2.0 for spec and docs; the names and logo are excluded (repo `README.md`) |
| Announced | 2026-10-06, by Bret Taylor and Clay Bavor of Sierra, as "an open standard Meta and Sierra are developing along with industry partners" ([Sierra](https://sierra.ai/blog/introducing-personal-agent-protocol)) |
| First draft | 0.1 on 2026-10-09 ([Sierra](https://sierra.ai/blog/poppy)) |
| Current | 1.0, dated 2026-11-14 in the repo's `content/versions/versions.json`; Sierra's post is dated 2026-11-13 ([Sierra](https://sierra.ai/blog/releasing-poppy)). 1.1 is an unpublished draft. |

**The problem it solves.** The spec's introduction says that today "it is all or nothing. Either
the agent passes as the user, signing in with their password and clicking through pages built for
people, or the company blocks it and it can't do anything." The user cannot limit the agent once
it is in, and the company cannot tell an agent from a person
([introduction](https://personalagentprotocol.org/docs/introduction)). Poppy adds points in
between: anonymous agent access, signed-in access limited to scopes the person approved, and
approval of individual actions.

**Three parties** (spec section 2): the User, the Personal Agent ("software acting for the User")
and the Company.

**How it works** (spec 1.0 and draft 1.1, sections 3 to 9):

1. **Discovery.** The company publishes `https://{domain}/.well-known/poppy.json`. It lists OAuth
   scopes with plain-language descriptions, APIs (`openapi` or `mcp`), a company-agent
   conversation endpoint, an optional endpoint for joining a browser, and extensions.
2. **Agent identity.** The agent's `client_id` is an HTTPS URL that serves a metadata document
   with a `jwks_uri`, following the IETF OAuth Client ID Metadata Document draft (section 4.1).
   The company decides which agents it accepts; "how it approves them is outside this
   specification".
3. **Sessions.** Every request to a company API or endpoint carries a `Poppy-Session` header: a
   JWT signed per request with a short-lived "delegated key" that a key in the agent's `jwks_uri`
   vouches for. It names a session and a user ID that is stable but different at each company
   (section 5). Signed-out use needs only this header.
4. **Sign-in.** Standard OAuth. "Direct Sign-In" is the authorization code grant with PKCE on the
   company's own page; "Device Sign-In" is the device grant. The agent authenticates with
   `private_key_jwt` (section 4). A transitional "Mediated Sign-In" extension, where the agent
   handles the person's password, is planned for removal on 2027-03-17.
5. **Three channels.** APIs (OpenAPI or a remote MCP server), conversations with the company's
   agent, and web browsing. The guides tell agents to "prefer the company's APIs and company agent
   over browsing its website".
6. **Web browsing** (section 6). The agent's browser loads a company page that hands it a one-time
   code. The agent authorizes that code in a separate signed request, the browser submits it, and
   the company sets its own cookie tying that browser to the session and its scopes. The access
   token never passes through the browser.
7. **Extensions.** `operations` (approve exact terms before an action; performed at most once),
   `browser-control` (company marks steps the person must take themselves), `ucp` (shopping via
   Universal Commerce Protocol), `links`, `disclosures`, `mediated-sign-in`.

## Maturity and adoption

Signs of momentum:

- Six versions in five weeks: 0.1 (10-09), 0.2 (10-24), 0.3 (11-04), 0.4 (11-10), 1.0 (11-14),
  with 1.1 in draft (`versions.json`).
- About 100 design partners listed in the introduction, including Meta, OpenAI, Shopify, Stripe,
  Visa, Mastercard, PayPal, Cloudflare, Okta, 1Password, Browserbase, Salesforce, Walmart and
  Target.
- Sierra says Poppy is on for everyone who uses Meta's Muse, which "automatically looks for Poppy
  first on every site it visits", and that "every Shopify store now automatically publishes a
  Poppy file" ([Sierra, 11-13](https://sierra.ai/blog/releasing-poppy)).
- Observed directly on 2026-11-25: `https://mercury.com/.well-known/poppy.json` returns a live
  document. It declares `protocol_version` 0.4 and offers one channel, an MCP server at
  `https://mcp.mercury.com/mcp`.

Signs of immaturity:

- No foundation or standards body. The site names no governing organization. Feedback goes
  through GitHub issues under a broad feedback license
  ([contribution terms](https://personalagentprotocol.org/license/contributions)).
- One author in practice. The GitHub contributors list shows 148 commits from one account and 11
  from two others. The org has a single repository.
- The repository is the documentation site only: it "does not implement the APIs the
  specification describes" (`README.md`). The reference implementation promised at launch was not
  found. There is a company implementation kit with a validator; no kit or SDK for personal agents
  was found.
- The 1.0 changelog and roadmap still list large open areas: signed approvals, payments, push
  notifications, delegated sign-in, attachments and self-hosted agents.
- Being a design partner is not the same as having shipped. The introduction says only that the
  authors "are working through implementations with several of these partners".
- Anthropic, Google, Apple and Microsoft are not on the partner list in the repo as of the commit
  above. No statement from any of them was found.

## Fit with neighbouring efforts

Only as far as needed to judge fit. The first three rows are from the Poppy spec itself. The
descriptions of A2A, NLWeb and the payment protocols are from general knowledge and were not
re-checked against their own sources for this ticket.

| Effort | Relation to Poppy |
| --- | --- |
| MCP | Used, not replaced. A company can list a remote MCP server as an API; Poppy adds the session header and its own sign-in in front of it (section 7). |
| WebMCP (tools a page exposes to a browser's agent) | Complementary and mostly unaddressed. The spec mentions WebMCP tools only in passing (browser-control section 5, UCP extension). How a company's page should talk to the agent is an open question upstream ([#105](https://github.com/personal-agent-protocol/personal-agent-protocol/issues/105)). |
| UCP (Universal Commerce Protocol) | Complementary. Poppy finds the company and signs the user in; shopping and checkout happen through UCP (`ucp` extension). |
| A2A (agent-to-agent messaging) | Overlaps with Poppy's conversation channel. Poppy defines its own conversation format and the only defined protocol type is `poppy` (section 8.1). The list is typed, so others could be added. The spec does not mention A2A. |
| NLWeb (natural-language query endpoints for sites) | Not mentioned in the spec. Different layer: site content querying, not identity or permission. |
| Agent payment protocols (AP2, Agentic Commerce Protocol) | Not mentioned in the spec. Payments are a roadmap item, described as "using existing payment and checkout protocols rather than replacing them". |

The piece Poppy adds that the others lack is the pairing of agent identity with per-person
permission that carries across API, conversation and website.

## Could Coracle support it?

### Role

Coracle would be the **Personal Agent**: the software acting for one person. It would never be the
Company. Claude would be the model inside that agent. The protocol does not care which model is
used, and section 10.2 requires tokens and keys to be kept "out of model context", which matches
native browser code holding secrets while Claude sees only page content and tool results.

### What a conforming Personal Agent has to implement

- Fetch and validate `poppy.json` and the OAuth metadata (section 3).
- Publish a client metadata document and key set at a public HTTPS URL (4.1).
- Sign a `Poppy-Session` JWT for every request with delegated keys, one per user ID, with
  delegations of at most 24 hours (5.2).
- Assign and store an opaque user ID per company (5.1).
- OAuth authorization code with PKCE, `private_key_jwt` client assertions, refresh, revocation;
  optionally DPoP and the device grant (section 4).
- For browsing: the browser-join flow, with the code read and authorized "in software its model
  can't read" (section 6).
- Recommended: Web Bot Auth HTTP message signatures so bot defences recognise the operator (5.3).
- Optional: MCP and OpenAPI clients, the conversation protocol, and the extensions.

Parts of this suit a browser well. Coracle can open the company's sign-in page in a normal tab
and catch the redirect itself; the spec allows loopback redirects for desktop apps (4.1, citing
RFC 8252). The `browser-control` extension (hand the page to the person, expose
`navigator.poppy.controller`) is something a browser can do natively.

### Conflict 1: identity needs a public URL and a protected key

- "A Personal Agent's `client_id` MUST be an HTTPS URL that returns its metadata document" (4.1),
  and the agent "is a confidential OAuth client" (section 4).
- The guides say: "Don't put your signing private key in an app you distribute. Anyone could
  extract it and act as your personal agent. Keep the key on your server, and have the app ask the
  server to sign assertions."
- For an open-source app with no backend, that leaves three options, none clean:
  - **The project runs a small signing service.** The spec's blind signing (10.7) would stop the
    service learning which companies a person uses. It is still a backend, and a blind signer
    signs whatever any install sends it.
  - **Each person publishes their own identity.** The metadata document and key set are static
    files, so this needs static hosting only. But a per-person `client_id` identifies that person
    at every company, which defeats the per-company user ID, and companies that allowlist known
    agents would not know it.
  - **Wait.** Upstream issue
    [#114](https://github.com/personal-agent-protocol/personal-agent-protocol/issues/114) proposes
    letting an agent register its own key with a company "so identity doesn't need a public URL".
    It is an open 1.1 proposal, not accepted text.
- Other local-first agent builders have raised the same problem
  ([#31](https://github.com/personal-agent-protocol/personal-agent-protocol/issues/31),
  [#42](https://github.com/personal-agent-protocol/personal-agent-protocol/issues/42)). The
  roadmap's "Self-hosted personal agents" entry says: "Browser extensions, and acting in the
  User's own signed-in browser, are still open."
- Even signed-out use needs this identity, because companies verify the session header against
  the agent's published keys (5.3). Only reading `poppy.json` needs nothing.

### Conflict 2: "never the User's own browser"

- Section 6, in 1.0 and draft 1.1: "The Personal Agent MUST join only a browser it controls to a
  Session, never the User's own browser. Otherwise, the Company would treat the User's own visits
  as the Personal Agent's."
- The maintainer wrote on 2026-11-06 that they are "inclined to go further and treat acting in
  the User's own signed-in browser as outside Poppy's scope", because a signature "doesn't limit
  what the agent can do with the User's cookies"
  ([#32](https://github.com/personal-agent-protocol/personal-agent-protocol/issues/32), still
  open).
- The same comment gives the workaround: the agent uses "its own browser instance ... That
  instance can still run on the User's device, with its own profile and cookies, and stay visible
  so the User can watch, correct, or stop it."
- Coracle's glossary already has the needed concept. A **profile** is "one isolated set of
  cookies, logins and site data". A profile reserved for the agent, shown in its own space, looks
  like a reasonable reading of "a browser it controls". The guides ask for "a separate browser
  storage context, with its own cookies and local storage, for each session". Whether maintainers
  would accept an agent-only profile inside the person's everyday browser as conforming has not
  been asked or answered; this is my reading.

### Complement or compete with Claude driving the page?

- **Complement, at a different layer.** Poppy decides who the agent is and what it may do. Claude
  still reads, decides and acts. On the API channel Claude would call the company's MCP tools; on
  the conversation channel it would talk to the company's agent; on the web channel it would drive
  pages in a joined, scoped session.
- **A different route for logged-in work.** Coracle's obvious mode is Claude acting in the tab
  where the person is already signed in. That is exactly the "passes as the user" behaviour Poppy
  was written to offer an alternative to, and it sits outside the protocol. Supporting Poppy would
  mean a second mode: the agent works in its own profile with access the person granted on the
  company's consent page.
- **The two can coexist.** "Implementing Poppy doesn't require using it with every Company that
  publishes `poppy.json`" (4.1). Where Coracle does use Poppy with a company that lists a browser
  join endpoint, it must join before browsing there.
- **A risk to the direct mode, not from implementing Poppy.** The introduction notes some
  companies already block agent traffic. If Poppy spreads, companies have a stronger reason to
  block or restrict agents that do not identify themselves. A company can also set `web.disabled`
  to ask agents to stay off its website, though "the protocol can't enforce" it (section 6).

### What this suggests for the plan

1. Do not put Poppy in v1. It cannot be implemented faithfully without a backend today, and the
   parts that matter to Coracle are the unsettled ones.
2. Keep the door open cheaply: let the AI session run in a profile of its own, separate from the
   person's logged-in profiles, as one supported mode. That is useful for safety regardless, and
   it is the shape Poppy expects.
3. A possible low-cost first step later is read-only discovery: fetch `poppy.json`, show that a
   site supports agents, and surface its listed MCP server. This needs no identity. Whether those
   servers accept a client that sends no Poppy session header is up to each company and was not
   tested.
4. Revisit when any of these change: #114 (key registration without a public URL), #32 (the
   user's own browser), #42 (signing without the publisher's server), or Anthropic taking a
   position.

## What could not be verified

- **Meta's side.** That Muse checks for Poppy on every site comes from Sierra's post. Meta's own
  Muse announcement was not found to mention the protocol.
- **Shopify.** The claim that every store publishes a Poppy file was not confirmed. One Shopify
  storefront tried returned a bot-check page, and no positive example was observed.
- **Production use.** Mercury serves a discovery file (at version 0.4, behind the published 1.0).
  No end-to-end session was attempted, so whether it works for an arbitrary agent is unknown.
- **Reference implementation.** Promised on 2026-10-06; not found in the GitHub org or on the
  site. It may exist privately or elsewhere.
- **Anthropic's position.** Absent from the partner list; no statement found. Unknown, not
  negative.
- **Neighbouring protocols.** A2A, NLWeb, AP2 and Agentic Commerce Protocol descriptions are from
  general knowledge, not re-verified.
- **Sierra's whitepaper** ("Personal agents and the enterprise") was not read.

## What was searched

- Web search for Sierra, "personal agent", protocol, Poppy, Meta Muse, and reactions from
  Anthropic, Google and Apple.
- Sierra's three blog posts and blog index.
- The spec site and a full clone of the spec repository (spec 1.0 and draft 1.1, guides,
  extensions, introduction, changelog, `versions.json`).
- GitHub issues #31, #32, #42, #53, #105 and #114 on the spec repository, and its contributor
  list.
- Direct requests for `/.well-known/poppy.json` on seven domains.

## Sources

- Sierra, "Introducing Personal Agent Protocol", 2026-10-06: <https://sierra.ai/blog/introducing-personal-agent-protocol>
- Sierra, "Sharing a draft of Personal Agent Protocol", 2026-10-09: <https://sierra.ai/blog/poppy>
- Sierra, "Releasing Personal Agent Protocol 1.0", 2026-11-13: <https://sierra.ai/blog/releasing-poppy>
- Spec 1.0: <https://personalagentprotocol.org/docs/1.0/spec>
- Introduction and roadmap: <https://personalagentprotocol.org/docs/introduction>
- Guides: <https://personalagentprotocol.org/docs/1.0/guides>
- Browser Control extension: <https://personalagentprotocol.org/docs/1.0/extensions/browser-control>
- Changelog: <https://personalagentprotocol.org/docs/changelog>
- Spec repository: <https://github.com/personal-agent-protocol/personal-agent-protocol>
- Upstream issues: [#31](https://github.com/personal-agent-protocol/personal-agent-protocol/issues/31), [#32](https://github.com/personal-agent-protocol/personal-agent-protocol/issues/32), [#42](https://github.com/personal-agent-protocol/personal-agent-protocol/issues/42), [#53](https://github.com/personal-agent-protocol/personal-agent-protocol/issues/53), [#105](https://github.com/personal-agent-protocol/personal-agent-protocol/issues/105), [#114](https://github.com/personal-agent-protocol/personal-agent-protocol/issues/114)
- Mercury's discovery file: <https://mercury.com/.well-known/poppy.json>
- Meta, "Introducing Muse" (found by search, for context on Muse only): <https://about.fb.com/news/2026/09/introducing-muse>
