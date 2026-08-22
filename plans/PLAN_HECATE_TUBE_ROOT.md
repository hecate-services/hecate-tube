# Plan: hecate-tube — Handover for the Full Event-Storming Session

**Status:** Handover doc for the storming session below is DONE. Full
event-storming pass (both aggregates, the live→clip policy, and the
macula-realm-side shape) plus resolution of every open question is now
captured in `plans/EVENT_STORM_HECATE_TUBE.md` — **read that doc**, this one
stays as the historical handover/hard-won-facts record. Next session should
start from that doc's §10 punch list, not from the open questions below
(they're resolved there, this section is kept for history per this
project's "never delete features" rule).
**Created:** 2026-08-22
**Last Updated:** 2026-08-22 (storming pass completed same day, see
`EVENT_STORM_HECATE_TUBE.md`)

---

## Read this first

- **Product spec:** `specification/SPECIFICATION.md` (in this repo) — the
  what and why. Read it before this doc if you haven't already.
- **This doc:** the how-we-got-here, what's-already-built, and
  hard-won-technical-facts-so-you-don't-re-derive-them doc.
- **Upstream:** `hecate-om/plans/PLAN_MACULA_API_INTEGRATION_SURVEY.md` —
  the survey that started this whole thread. Its recommended hecate-om
  wrapper design is NOT yet built; hecate-tube is deliberately being built
  first, against raw macula SDK primitives, so hecate-om's design gets
  derived from one complete, real exemplar instead of speculation. See
  that doc's "Recommended design" section for the deferred plan.

## The instruction for next session, explicitly

The user's own words: **"Let's storm the whole thing first, resolve
questions after."** Do the full event-storming pass — both aggregates in
hecate-tube (Channel, VideoClip), the live→clip process manager, AND the
macula-realm-side `tube`/`tube_web` aggregator's own shape (what it
projects, what it serves) — captured as one skill artifact.
**Do not stop to resolve the six open questions in
`specification/SPECIFICATION.md` §6 along the way** — note where they bite,
keep storming, resolve them as a batch at the end. This ordering is
deliberate, not a default — preserve it.

---

## How we got here (the arc, compressed)

1. `hecate-om/plans/PLAN_MACULA_API_INTEGRATION_SURVEY.md` — surveyed how
   to wrap macula's supervised primitives (RPC/PubSub/Content/Streaming) at
   the hecate-om level, using four existing DIY hecate-services repos as
   signal. Found a confirmed gap: hecate-om's RPC wrapper only does DHT
   discovery, never wires an actual responder. Produced a recommended
   design, explicitly NOT yet implemented.
2. User proposed a different methodology: build ONE complete new service
   that genuinely needs all four primitive pairs, make it work completely,
   THEN derive hecate-om's updates from that — rather than generalizing
   from fragmentary DIY signal. Landed on **"YouTube over mesh"**
   (`hecate-tube`) as the exemplar, since upload/watch, live broadcast,
   follow/notify, and metadata lookup map honestly onto Content, Streaming,
   PubSub, and RPC respectively.
3. Entered plan mode, researched hecate-om's own scaffolding tooling and
   hecate-mpong-bot's proven CMD/PRJ/QRY shape, wrote and got approval for
   a phased implementation plan (`/home/rl/.claude/plans/vast-stirring-lagoon.md`
   — the approved plan-mode artifact; superseded in scope by this doc now
   that the real spec landed, but its scaffolding/methodology notes still
   hold).
4. Built and fully verified **Phase 0** (the walking skeleton) — see below.
5. User gave the **real, detailed product spec** (now in
   `specification/SPECIFICATION.md`) — richer than the original plan's
   guesses in several load-bearing ways (streamed-not-downloaded being the
   biggest correction). This handover exists because that spec arrived
   mid-build and the right move is a full re-storm before writing more
   code, not patching Phase 0 sideways.

---

## What's already built (Phase 0 — walking skeleton, fully verified)

Repo: `/home/rl/work/github.com/hecate-services/hecate-tube`. **Not yet a
git repo** — scaffolding left `git init` as a manual step, deliberately not
taken yet (see "Nothing is committed" below).

### Current file tree

```
apps/hecate_tube/           top-level app: hecate_om_service impl, HTTP listener sup
  src/hecate_tube_app.erl, hecate_tube.app.src, hecate_tube_service.erl, hecate_tube_sup.erl
  test/hecate_tube_service_tests.erl        (scaffold-generated, patched — see below)
apps/guide_tube_lifecycle/  CMD department
  include/tube_channel_status.hrl           (bit-flag status defines)
  src/channel_aggregate.erl, channel_state.erl
  src/initialize_channel/                   (command + event + handler triad)
  test/channel_aggregate_tests.erl          (pure unit tests, no live dispatch)
apps/project_tube/          PRJ department
  src/project_tube_store.erl                (ETS read-model facade)
  src/channel_lifecycle_to_channels/        (evoq_projection)
apps/query_tube/            QRY department
  src/get_channel_by_id/get_channel_by_id_api.erl   (cowboy handler)
specification/SPECIFICATION.md              product spec (new, this session)
plans/PLAN_HECATE_TUBE_ROOT.md              this doc
config/sys.config(.src), rebar.config, Containerfile, deploy/, .github/workflows/, scripts/health.sh
  -- all scaffold-generated, patched for CMD/PRJ/QRY wiring (see below)
```

**This entire `channel` aggregate/desk shape is now known to be too thin**
against the real spec (needs description/owner/tags/logo, a real
upload→publish→retract lifecycle for clips, a live→clip transition). It
proved the *mechanism* end-to-end; it is not the final domain model. Expect
the event-storming pass to replace most of `guide_tube_lifecycle`'s desks.
`hecate_tube`/`project_tube`/`query_tube`'s department-app *scaffolding*
(sup/app.src shape, ETS store-facade pattern, cowboy routing aggregation)
stays valid regardless of what the aggregates turn into.

### Verified working, end-to-end, for real

1. `rebar3 compile` — clean, all four apps, zero warnings
   (`warnings_as_errors` is on).
2. `rebar3 eunit` — 20/20 passing. Pure logic only (aggregate/handler/state,
   no live dispatch) — deliberate, since live dispatch needs a real
   evoq/reckon-db boot that eunit doesn't provide.
3. **Live boot smoke test** (the thing that actually matters — proves the
   wiring, not just the logic): booted the real release-shaped app via
   `erl` with `config/sys.config`, called
   `maybe_initialize_channel:dispatch/1` for real, watched the event land
   in reckon-db, watched the projection pick it up, then hit
   `GET /api/tube/channels/:id` over real HTTP and got `200` with the
   projected row back. Full path: CMD → evoq → reckon-db → PRJ projection →
   ETS → QRY → cowboy → HTTP. **This pattern is the reusable verification
   technique for every phase from here on** — eunit alone will not catch
   wiring bugs (it didn't; the smoke test did, twice). See "Smoke-test
   harness" below for the exact reusable recipe.

### Real bugs found and fixed along the way (not worked around)

1. **hecate-om's own `hecate_service` scaffold template** pinned
   `{hecate_om, "~> 0.8"}` — six major versions stale. Fixed at the source:
   `hecate-om/priv/templates/hecate_service/rebar.config` now pins
   `~> 0.13`. **Uncommitted** in hecate-om (see below).
2. **hex.pm reality check**: hecate-om's local `.app.src` says `0.14.0`,
   but hex.pm's latest published release is `0.13.0` — 0.14.0 was never
   published (publishing is an explicit user-manual step per this
   project's CLAUDE.md; not something to do unprompted). hecate-tube's
   `rebar.config` pins `~> 0.13`, matching what's real, not what's local.
   **If a later session bumps hecate-om's own version and wants
   hecate-tube on it, re-check hex.pm first** — don't assume the local
   `.app.src` number is published.
3. **Cowboy tilde-arrow granularity gotcha**: `{cowboy, "~> 2.12"}`
   resolves 2.18.x, whose cowlib requirement conflicts with what
   macula/hecate_om pin. Fixed to the tight `{cowboy, "~> 2.12.0"}` form
   (matches hecate-mpong-bot/hecate-llm's own pin — this is a known,
   already-worked-around issue elsewhere in the workspace, not novel).
4. **A genuine, easy-to-repeat evoq gotcha** (see "evoq API reference"
   below, §"event shape on the wire") — a projection reading event fields
   as top-level keys will compile fine, pass eunit (if the eunit test
   makes the same wrong assumption, as mine initially did), and then
   silently never fire in production because `project/4` crashes on
   `{badkey, ...}`, the supervised child restarts, and nothing surfaces the
   failure to a fixed-interval poll. **Every future projection needs
   `maps:get(data, Event)` unwrapped first.** This one is worth its own
   paragraph in whatever eventually gets written back to hecate-om or
   evoq's own docs.
5. Generated `hecate_tube_service_tests.erl`'s
   `supervisor_starts_and_stops_test` assumed an empty children list (true
   at scaffold time); patched once a real HTTP-listener child was added —
   needed `application:ensure_all_started(cowboy)` first (ranch_server
   isn't running under bare eunit) and the child id is
   `{ranch_listener_sup, Name}`, not bare `Name`.

### Load-bearing infra decision, already made and correct: two separate HTTP listeners

`hecate_om_sup` (started automatically by `hecate_om:boot/1`, before the
service's own `start/1`) **already** runs its own cowboy listener on
`health_port`, serving `GET /health` via `hecate_om_health_handler:routes()`
— confirmed by reading `hecate_om_sup.erl` directly. hecate-tube's own
`hecate_tube_sup` runs a **second, separate** listener on its own
`http_port` (app env under the `hecate_tube` key, not `hecate_om`),
carrying only this service's business routes. Do not merge these or reuse
`health_port` for business routes — hecate-mpong-bot's older code did
something adjacent to work around a since-fixed bug where hecate_om's
health route wasn't mounted at all; that workaround is now obsolete
upstream, don't copy it.

---

## Hard-won technical reference (verified by reading source, not assumed)

### evoq API — the parts that matter, precisely

evoq 1.23.0 (pinned; matches what's actually on hex and what mpong-bot
uses). Source read in full at
`/home/rl/work/github.com/reckon-db-org/evoq/src/`.

- **Command behaviour** (`evoq_command`): required `command_type() ->
  atom()`, `new(Params :: map()) -> {ok, Command} | {error, Reason}`,
  `to_map(Command) -> map()`. Optional `validate/1`, `from_map/1`.
- **Event behaviour** (`evoq_event`): required `event_type() -> atom()`
  *(the spec says atom; hecate-mpong-bot's real code returns a BINARY
  and evoq's own runtime tolerates both — `evoq_aggregate:resolve_event_type/1`
  normalizes either shape to binary for storage. Followed mpong-bot's binary
  convention in Phase 0; this is a real, pre-existing, low-priority
  spec/practice mismatch in evoq itself, not something to "fix" mid-build)*,
  `new(Params) -> Event`, `to_map(Event) -> map()`. Optional `from_map/1`.
- **Aggregate behaviour** (`evoq_aggregate`): required `state_module() ->
  module()`, `init(AggregateId) -> {ok, State}`, `execute(State, Command ::
  map()) -> {ok, [Event :: map()]} | {error, Reason}`, `apply(State, Event
  :: map()) -> NewState`. Aggregates are real per-stream-id gen_server
  processes, started on demand by evoq's own registry — nothing to
  supervise yourself.
- **State behaviour** (`evoq_state`): required `new(AggregateId) -> State`,
  `apply_event(State, Event) -> State`, `to_map(State) -> map()`.
- **Dispatch entry point**: `evoq_router:dispatch(Command :: #evoq_command{})`
  or `dispatch(Command, Opts)` → `{ok, Version, [Event]} | {error, Reason}`.
  **`evoq_dispatcher` does NOT exist** in this evoq version despite
  hecate-mpong-bot's real code calling it — mpong-bot's code either
  predates a rename or was never actually exercised against this evoq
  version. Use `evoq_router:dispatch/1,2`, confirmed working.
  Build the command via `evoq_command:new(CommandType, AggregateType,
  AggregateId, Payload, Metadata)`, not by hand-constructing the record —
  it fills in `command_id`/`correlation_id` for you.
- **Store id resolution**: `evoq_execution_context:new/2` reads
  `maps:get(store_id, Opts, application:get_env(evoq, store_id,
  default_store))` — so with `{evoq, [{store_id, tube_store}, ...]}` in
  sys.config, you never need to pass `store_id` in `Opts` at dispatch time.
- **Projection behaviour** (`evoq_projection`): required `interested_in()
  -> [binary()]`, `init(Config) -> {ok, State, ReadModel}`, `project(Event,
  Metadata, State, ReadModel) -> {ok, NewState, NewReadModel} | {skip, ...}
  | {error, Reason}`. Started via `evoq_projection:start_link(Module,
  Config, Opts)` as an ordinary supervised child — auto-registers itself
  with `evoq_event_type_registry` for its declared event types.
- **Event shape on the wire — THE GOTCHA**: what `project/4` actually
  receives is built by
  `evoq_store_subscription:evoq_event_to_routable/1`:
  `#{event_type, event_id, stream_id, version, data, tags, timestamp,
  epoch_us}`. **Your event's own fields (whatever `to_map/1` produced) are
  nested under `data`, not top-level.** `evoq_projection:do_project/...`
  merges `event_type` onto this same map before calling your `project/4` —
  it does NOT flatten `data`. Every projection must do
  `#{event_type := T, data := Data} = Event` then read fields off `Data`.
  Also: field keys surviving the store round-trip are not guaranteed to
  stay atoms — write field-getters that tolerate both atom and binary keys
  (see `channel_lifecycle_to_channels.erl`'s `field/2` for the pattern,
  same shape as `channel_state.erl`'s `field/2` for aggregate replay).
- **Delivery mechanism** (for context, not something you need to touch):
  `evoq_store_subscription` runs one `$all`-stream subscription per store,
  replays history on boot (`catch_up_historical/1`), then routes live
  events via `evoq_event_router:route_event/2` → looks up registered
  handler pids in `evoq_event_type_registry` → `evoq_event_handler:notify/4`
  (`gen_server:call(Pid, {notify, EventType, Event, Metadata}, infinity)`)
  → lands on `evoq_projection`'s matching `handle_call({notify, ...})`
  clause. Message shapes line up correctly; the only real gotcha is the
  `data`-nesting above.

### `reckon_gater_stream_id` — the current stream-id convention

`/home/rl/work/github.com/reckon-db-org/reckon-gater/src/reckon_gater_stream_id.erl`.
Format: `<prefix>-<32 lowercase hex>`, prefix `[a-z]{1,32}`. **`new(Prefix)`
mints a fresh, valid id — it does NOT derive one from an existing external
id.** The right pattern (used in `initialize_channel_v1:new/1`): mint the
id AT construction time inside the command's own constructor, and use it
directly as the stream id (no separate derivation step). This deliberately
diverges from hecate-mpong-bot's own `<<"mpong_game-", GameId/binary>>`
hand-rolled pattern, which predates this module and trips hecate-corpus
antipattern #51 (human-readable stream ids → silent empty-store failure).

### Scaffolding tooling (for whatever new desks/apps get added)

- `hecate-om/scripts/scaffold-service.sh <repo-name> "<desc>" [port]` — runs
  `rebar3 new hecate_service ...`, generates the base substrate app only
  (mesh join, `/health`, no CMD/PRJ/QRY). Already used once for this repo;
  re-running would only be relevant for a brand-new service, not for
  hecate-tube's own further desks.
- **No generator for CMD/PRJ/QRY department apps** — hand-authored,
  mirroring hecate-mpong-bot's proven shape (one CMD app can host multiple
  aggregate types as sibling top-level modules + desk subdirectories; one
  PRJ app, one QRY app, each with their own thin `rebar.config` whose
  `src_dirs` must explicitly list every desk directory AND `"test"` if the
  app has a `test/` dir — **an explicit `src_dirs` list REPLACES rebar3's
  default `["src", "test"]`, it doesn't extend it; omitting `"test"`
  silently drops that app's eunit suite from every run**, and this bit
  Phase 0 once already).
- `hecate-corpus/templates/erlang/*.tmpl` — per-file codegen templates
  (`cmd_spoke`, `qry_byid_api`/`qry_page_api`, `projection`,
  `process_manager`, ...) — **evaluated and deliberately NOT used**: they
  model an older/simpler pattern (`reckon_evoq:append/4` direct-append, no
  `evoq_aggregate`/`evoq_command`/`evoq_event` behaviours) that skips the
  aggregate's own business-rule enforcement — closer to hecate-corpus
  antipattern #39 (bypassing evoq behaviours) than to what real, working
  services (hecate-mpong-bot) actually do. hecate-llm's similar
  `hecate_api_utils`-based QRY pattern was also evaluated and rejected: the
  module it imports (`hecate_api_utils`) lives only in the old
  `hecate-daemon` monolith and was never actually carried over during
  hecate-llm's extraction — hecate-llm's own CHANGELOG confirms it's an
  incomplete, mid-extraction scaffold, not a clean reference. **Keep
  mirroring hecate-mpong-bot's proven shape**, not either of these.

### `macula-realm` — confirmed existing, structurally ready

`/home/rl/work/github.com/macula-io/macula-realm/system/` is a real,
existing Phoenix umbrella app (`mix.exs` at that path) already using the
identical CMD/PRJ/QRY naming convention: `apps/guide_realm_lifecycle`,
`apps/project_realm`, `apps/project_realm_identities`,
`apps/query_realm`, `apps/query_realm_identities`,
`apps/macula_realm` (domain), `apps/macula_realm_web` (Phoenix web).
Checked `SERVICES.md`/`ROADMAP.md` — no existing "tube" work there; clean
slate. The natural shape for the consumer-facing side of this spec is new
sibling apps in that same umbrella (`tube`, `tube_web`, plus whatever
`project_tube_catalog`/`query_tube_catalog` the aggregator's own read model
needs) — not a new repo, not a new stack decision to make.

### Smoke-test harness — the reusable verification recipe

eunit did not catch either real bug found in Phase 0 (both were wiring/data
-shape issues that only a live boot exercises). The recipe that did catch
them, worth reusing for every future phase:

```bash
cd hecate-tube
rebar3 compile   # NOT `rebar3 eunit` -- eunit compiles into _build/test/,
                 # a different profile from _build/default/ that a manual
                 # `erl -pa` boot needs. This exact mismatch cost real time
                 # once already -- recompile default before every smoke test.
ABS_EBIN_PATHS=$(find "$(pwd)/_build/default/lib" -maxdepth 2 -type d -name ebin)
# absolute paths matter -- relative -pa paths misbehaved once, not fully
# root-caused, not worth re-debugging, just use absolute.
erl -noshell $(for p in $ABS_EBIN_PATHS; do echo -n "-pa $p "; done) \
    -pa <scratch-dir-with-a-compiled-smoke-test-module> \
    -config "$(pwd)/config/sys.config" \
    -eval 'smoke_test:run().'
```

Write the actual test logic as a real compiled `.erl` module (`erlc -o
<scratch-dir> smoke_test.erl`), not stacked `-eval` flags — bindings don't
persist across separate `-eval` invocations, learned the hard way. Poll
with a bounded retry loop rather than a fixed `timer:sleep`; a few hundred
ms fixed sleep gave false negatives once (turned out to be the stale-beam
issue above, not real latency, but the polling pattern is the right
defensive shape regardless). `HECATE_DATA_DIR` must point somewhere
writable (`/var/lib/hecate-tube` default isn't) — set it in the env before
`erl` starts.

---

## Nothing is committed to git anywhere yet

- **hecate-tube**: not a git repo at all. `git init -b main && git add .
  && git commit` is still a manual, un-taken step (per the scaffold's own
  post-generation instructions, and per this project's git-safety rule:
  only commit when explicitly asked).
- **hecate-om**: two uncommitted local changes —
  `plans/PLAN_MACULA_API_INTEGRATION_SURVEY.md` (the finished survey
  write-up) and `priv/templates/hecate_service/rebar.config` (the stale
  version-pin fix, §"Real bugs found" #1 above). Not committed, not
  pushed, not published to hex — all deliberately left for the user's
  explicit go-ahead.

---

## Design conversation so far — proposals, not yet validated

Kept in full per the user's explicit request ("your suggestions so far are
interesting, keep them in"). None of this is confirmed; all of it is
input to the event-storming session, not a decision.

### Revised primitive-pair mapping (supersedes the original survey-era guess)

| Primitive | Role |
|---|---|
| **Streaming** | *All* viewing — live broadcast AND replay of a stored clip. Nothing is ever bulk-transferred to a viewer. |
| **Content** | Narrowed to thumbnails and channel logos — small, discrete, fetch-once, cacheable images. |
| **PubSub** | Integration facts: channel configured, clip published/retracted, went live/ended live — published by hecate-tube, consumed by the macula-realm `tube` aggregator (and possibly peer channels — open question). |
| **RPC** | Catalog/metadata lookups — a consumer or the realm aggregator asking a specific channel for a clip's full metadata on demand. |

### Event-storming first pass (starting point for the real session, not a conclusion)

```
Channel (owner-facing, edge node):
  configure_channel_v1   -> channel_configured_v1   (name, description, owner, tags, logo)
  go_live_v1             -> channel_went_live_v1     (session_id)
  end_live_v1            -> live_session_ended_v1     -> PM mints a VideoClip (see below)

VideoClip (one per upload OR per completed live session):
  upload_video_clip_v1   -> video_clip_uploaded_v1    (private -- edge node only)
  publish_video_clip_v1  -> video_clip_published_v1   (now discoverable/streamable)
  retract_video_clip_v1  -> video_clip_retracted_v1   (back to private)
  ??? (naming open)      -> video_clip_?????_v1       (permanent removal)
  (view counting -- ownership open, see specification/SPECIFICATION.md §6.2)
```

A completed live session needs a process manager that reacts to
`live_session_ended_v1` and mints a `VideoClip` — whether it starts
published or private is open question §6.4 in the specification doc.

### What the full storming pass still needs to cover, that this first pass didn't

- The macula-realm-side `tube`/`tube_web` shape itself: what it projects
  from incoming facts, what read model(s) it needs, what `TubeLive`
  (and possibly `VideoLive`) actually render and query.
- The exact **integration fact contracts** hecate-tube publishes — schema,
  topic naming, what's included vs. deliberately thin (mirroring the
  Domain-Events-vs-Integration-Facts split already established elsewhere
  in this workspace's conventions).
- Whether/how RPC (catalog/metadata lookup) is served BY hecate-tube (as
  Phase 4 of the original plan intended — closing the survey's confirmed
  provider-wiring gap) vs. served by the realm aggregator from its own
  cache.
- Logo/thumbnail upload+publish flow through Content, concretely.
- The live-streaming provider/consumer wiring itself (macula_streamer /
  macula_stream_sink), now serving BOTH live and VOD replay, not just live
  as originally scoped.

## Open questions — resolve AFTER the full storm, per explicit instruction

See `specification/SPECIFICATION.md` §6 — six questions, reproduced there
in full so this doc doesn't drift out of sync with it. Don't resolve them
mid-storm; note where they bite and keep going.

**Resolved 2026-08-22 — see `plans/EVENT_STORM_HECATE_TUBE.md` §8** for all
six, plus §9 for questions the storm itself surfaced that weren't on this
list (topic-namespace discovery, the `tube`/`tube_web` app-placement
correction, the unspecified live-ingest input side, and others).
