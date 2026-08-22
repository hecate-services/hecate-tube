## 0. How this storm was run

Grounded in, not guessed from: `hecate-corpus/philosophy/DDD.md` (the Dossier
Principle), `hecate-corpus/philosophy/HECATE_DOMAIN_LIFECYCLE.md`,
`hecate-corpus/philosophy/INTEGRATION_TRANSPORTS.md`,
`hecate-corpus/skills/NAMING_CONVENTIONS.md`, the antipatterns corpus
(`domain.md`, `integration.md`, `naming.md`, `event_sourcing.md`), the actual
Phase 0 source in this repo, hecate-mpong-bot's real desks (`advertise_game`,
`broadcast_game_state`, `discover_games`, `stream_mpong_game`,
`hecate_topics`) as the only *proven* mesh-integration precedent in this
workspace, macula's own `macula.erl` facade and `STREAMING_GUIDE.md`, and
macula-realm's real umbrella structure (`guide_realm_lifecycle`,
`project_realm`, `query_realm`, and the `Mpong`/`Mpong.Subscriber`/`MpongLive`
trio as the only *proven* realm-side mesh-consumer precedent).

The hecate-rag MCP tool returned no hits for every query tried (dev container
likely not running/seeded) — this storm reads the corpus files directly
instead, which is the more thorough path anyway since it isn't limited to
retrieved chunks.

---

## 0.5. The high-level macula API — what it is, and why it's the point

**This is why hecate-tube exists, stated precisely.** macula's own docs split
every primitive pair into a **Guide** (the supervised, daemon-facing layer
real applications use) and a **Protocol** doc (the raw wire primitives
underneath, for custom retry logic, observability, or another language's
SDK). The Guide layer is one, sometimes two, steps above `macula.erl`'s
facade functions:

| Primitive | Raw facade (facade, not "raw wire" — still one step up from Protocol) | Supervised wrapper (the actual "high-level API") |
|---|---|---|
| PubSub | `macula:publish/4,5`, `macula:subscribe/4,5` | `macula_publisher`, `macula_subscriber` |
| RPC | `macula:call/5`, `macula:advertise/5` | `macula_request`, `macula_response` (+ `_direct` variants) |
| Content | `macula:put_content/2`, `macula:get_content/2` | `macula_feeder`, `macula_download` (+ `_direct`); `macula_pusher`/`macula_upload` for a targeted push |
| Streaming | `macula:call_stream/5`, `macula:advertise_stream/5` | `macula_streamer`, `macula_stream_sink` (+ `_direct`) |

The wrappers aren't sugar. Each gets an addressable, supervisable,
cancellable pid, and each publishes its own `*.{received,replied,sent,
completed,started}_v1` mesh fact around every operation — free observability
neither the facade nor raw calls give you. **hecate-tube's own code calls
the wrapper module for every primitive pair it uses, never the bare
`macula:*` facade function when a wrapper exists for the same job**, and
never `macula_client`/`macula_pubsub`/`macula_content_transfer` internals
directly. This corrects every desk description in §5 below, which
originally named the plain facade calls.

**Verified against the actual wrapper source** (`src/macula_publisher.erl`,
`src/pubsub/macula_subscriber.erl`, `src/macula_request.erl`,
`src/macula_response.erl`, `src/macula_feeder.erl`, `src/macula_download.erl`,
`src/macula_streamer.erl`, `src/macula_stream_sink.erl` — read in full, not
inferred from the Guide prose) — the real exported signatures every desk
below now names:

| Wrapper | Signature | Callback module implements |
|---|---|---|
| `macula_publisher` | `start_link(Module, Pool, Realm, Topic, Payload, Args)` | `init/1`, `handle_published/2` |
| `macula_subscriber` | `start_link(Module, Pool, Realm, Topic, Args, Opts)` | `init/1`, `handle_event/4`, optional `terminate/2` |
| `macula_response` | `advertise/5,6`, `advertise_direct(Pool, Realm, Procedure, Module, Args, Identity, Opts)` | `init/1`, `handle_request/2 -> {reply, R, S} \| {error, R, S}` |
| `macula_request` | `start_link/6,7`, `start_link_direct/6,7,8` | `init/1`, `handle_reply/2` |
| `macula_feeder` | `start_link(Module, Pool, Realm, Bytes, Args)`; `start_link_direct(Module, Pool, Station, Realm, Bytes, Args)` — PUT names its own target `Station`, no resolve step | `init/1`, `handle_fed/2` |
| `macula_download` | `start_link(Module, Pool, Realm, Mcid, Args)`; `start_link_direct(Module, Pool, Realm, Mcid, Args)` — resolves the provider automatically from `content_announcement` | `init/1`, `handle_downloaded/2` |
| `macula_streamer` | `advertise/5,6`, `advertise_direct(Pool, Realm, Procedure, Module, Args, Identity, Opts)` | `init/1`, `handle_open/2`; `send/2,3` + `close/1` called on the streamer pid from *outside* |
| `macula_stream_sink` | `start_link/5,6`, `start_link_direct/5,6` | `init/1`, `handle_chunk/2`, optional `handle_close/2` |

Every provider-side `advertise_direct/6,7` (RPC and Streaming) takes an
`Identity :: macula_identity:key_pair()` — the service's own stable signing
keypair, reused across re-advertises. This is a second `{Pool, Realm}`-like
shared dependency every direct-dial provider desk needs, and it surfaces a
real hecate-om gap — see §12.

**One legitimate, precedented exception to "always the wrapper":** a
consumer that needs a *synchronous* answer (a query-shaped call site that
must return `{ok, Value} | {error, _}` to its own caller, not receive it
later via `handle_reply/2`) has a real, deliberate reason to call
`macula_direct_dial:call/6` (or `macula:call_station/6,7`) directly instead
of `macula_request:start_link_direct/6,7,8` — and hecate-om's own
`hecate_om_capabilities:call_capability/4` already makes exactly this choice,
for exactly this reason (documented in the survey's Question 3: the async
wrapper and synchronous multi-provider failover aren't reconcilable without
rebuilding most of what the wrapper would have removed). §7's
`Tube.RemoteLookup` follows the same precedent — noted there, not a
deviation from the rule above but a recognized second case of it.

**Why this is the actual point of the project, not a footnote.** hecate-om's
own `PLAN_MACULA_API_INTEGRATION_SURVEY.md` (read in full for this
follow-up) already reached the same Guide/Protocol vocabulary independently,
audited `hecate_om`'s real source, and found:

- **RPC consumer** (`hecate_om:call_capability/4`) — done, and deliberately
  *not* built on `macula_request:start_link_direct` (sync + built-in
  multi-provider failover vs. the wrapper's async single-resolve — a real
  trade-off, not an oversight; see the survey's Question 3).
- **RPC provider** — **the confirmed gap.** `hecate_om_capabilities.erl`
  writes `procedure_advertisement` DHT records (discovery) but never calls
  `macula:advertise/5` or `macula_response:advertise_direct/6,7` anywhere —
  a service is discoverable but **not callable**. This is the exact gap
  `PLAN_HECATE_TUBE_ROOT.md`'s own origin story names.
- **PubSub, Content, Streaming** — **zero wrapping in hecate-om today**,
  explicitly deferred by that survey "pending a real DIY need" — because at
  the time it was written, no service in this workspace had one. hecate-tube
  is that need, for real, for the first time.

So hecate-tube's own desks call the SDK's supervised wrappers **directly**,
not through hecate-om — not as a shortcut around it, but because for three
of the four primitive pairs (and the provider half of the fourth), hecate-om
has nothing to call yet. Building the real thing first and writing down what
repeats is exactly the survey's own methodology (its RPC-consumer
recommendation was built the same way, from four real DIY modules). §11-§12
carry this forward as a running, evidence-based log rather than a single
retrospective section.

---

## 1. Channel dossier

**Stream prefix:** `channel` (unchanged from Phase 0). **CMD app:**
`guide_tube_lifecycle` (unchanged — one CMD app, two aggregate types, per the
mpong-bot precedent the plan doc already cites).

### 1.1 Naming correction to Phase 0 (found by re-deriving against the corpus, not by opinion)

Phase 0's birth desk is `initialize_channel_v1` → `channel_initialized_v1`.
`NAMING_CONVENTIONS.md`'s Event Verb table and antipatterns/domain.md Demon
#4 both give the birth-event rule as `{noun}_initiated_v1`, and the real
precedent just read in macula-realm (`realm_initiated_v1`) confirms it.
"Initialized" is not the banned CRUD form ("created"), but it is also not the
convention's chosen word, and this project's specific goal is to derive
hecate-om's future guidance from one exemplar done *right* — so:

> **Rename `initialize_channel` → `initiate_channel`, `channel_initialized_v1`
> → `channel_initiated_v1`, `maybe_initialize_channel` →
> `maybe_initiate_channel`.** Same for the `initialized_at` field →
> `initiated_at`.

Also rename the `org` field → `owner`. Spec §5 lists `owner` as a named
Channel metadata field; `org` never appears in the spec and was Phase 0
scaffolding filler. One rename, no semantic change — `org` was always "who
runs this channel."

### 1.2 Status bit flags (`tube_channel_status.hrl`)

| Flag | Value | Meaning |
|---|---|---|
| `?CHANNEL_INITIATED` | 1 | Channel exists, dossier opened |
| `?CHANNEL_LIVE` | 2 | Currently broadcasting a live session |

### 1.3 Desks

| Desk | Command | Event | Payload (event) | Guard |
|---|---|---|---|---|
| `initiate_channel` | `initiate_channel_v1` | `channel_initiated_v1` | `channel_id, name, description, owner, tags, logo_mcid, initiated_at` | not already `?CHANNEL_INITIATED` |
| `reconfigure_channel` | `reconfigure_channel_v1` | `channel_reconfigured_v1` | `channel_id, name, description, tags, logo_mcid, reconfigured_at` | `?CHANNEL_INITIATED` set |
| `go_live` | `go_live_v1` | `channel_went_live_v1` | `channel_id, session_id, started_at` | `?CHANNEL_INITIATED` set, `?CHANNEL_LIVE` NOT set |
| `end_live` | `end_live_v1` | `live_session_ended_v1` | `channel_id, session_id, ended_at, duration_ms, recording_ref` | `?CHANNEL_LIVE` set |

`reconfigure_channel` covers spec §4's "Configure the channel" in full —
CRUD-taboo table gives "update_config → reconfigure_{thing}" as exactly this
shape, so no separate desk per field.

**`recording_ref` is load-bearing and easy to miss.** Per DDD.md's "data
enters through commands only" — the Live→Clip policy (§3) needs to know
*where the recorded bytes landed on disk* to mint a clip from them, and a
policy may never look that up itself (Demon #41, the cardinal sin). So
whatever component is recording the live feed to disk must hand its file
reference to the `end_live_v1` **command** at the moment the owner ends the
session, so it rides `live_session_ended_v1` into the policy. If nothing
produces this reference yet, that's this storm's biggest concrete gap — see
§9.3.

`owner` is set once at `initiate_channel` and does not appear in
`reconfigure_channel`'s payload — ownership transfer isn't in spec scope, so
there's no desk for it (minimal ceremony: don't build a field-that-can't-change
into a desk that implies it can).

---

## 2. VideoClip dossier

**Stream prefix:** `clip` (new). **CMD app:** `guide_tube_lifecycle` (sibling
aggregate to `channel`, same app, same store — see §8 for why this must be a
*separate* aggregate rather than embedded in `channel`, which is open
question §6.5).

### 2.1 Status bit flags (`tube_video_clip_status.hrl`, new file)

| Flag | Value | Meaning |
|---|---|---|
| `?VIDEO_CLIP_UPLOADED` | 1 | Bytes exist on disk, private |
| `?VIDEO_CLIP_PUBLISHED` | 2 | Discoverable/streamable on the mesh |
| `?VIDEO_CLIP_ARCHIVED` | 4 | Permanently retired (terminal) |

(Revised in the crafting session — see PART2 §16.4: a fourth flag,
`?VIDEO_CLIP_REJECTED` (8), was added for the scan pipeline's rejection
verdict. Original table kept here as written at storm time.)

### 2.2 Desks

| Desk | Command | Event | Payload (event) | Guard |
|---|---|---|---|---|
| `upload_video_clip` | `upload_video_clip_v1` | `video_clip_uploaded_v1` | `clip_id, channel_id, name, description, tags, thumbnail_mcid, local_ref, source (<<"uploaded">>\|<<"recorded">>), uploaded_at` | birth — no prior state |
| `publish_video_clip` | `publish_video_clip_v1` | `video_clip_published_v1` | `clip_id, channel_id, published_at` | `UPLOADED` set, `PUBLISHED` NOT set, not `ARCHIVED` |
| `retract_video_clip` | `retract_video_clip_v1` | `video_clip_retracted_v1` | `clip_id, channel_id, retracted_at` | `PUBLISHED` set, not `ARCHIVED` |
| `archive_video_clip` | `archive_video_clip_v1` | `video_clip_archived_v1` | `clip_id, channel_id, archived_at` | not `ARCHIVED` (from either `UPLOADED`-only or `PUBLISHED` state — an owner can discard an unpublished draft too) |
| `record_video_clip_view` | `record_video_clip_view_v1` | `video_clip_viewed_v1` | `clip_id, channel_id, viewed_at, viewer_ref` (nullable — anonymous viewers are the common case) | `PUBLISHED` set |

`retract` clears the `PUBLISHED` bit and leaves `UPLOADED` set — "Minimal
Ceremony" (DDD.md) applies directly: retract *is* the return-to-private
transition, no separate state machine needed, symmetric with `publish`.

`local_ref` is the edge-node-only file handle (path or similar) the
streaming desks in §5 read from. **It must never appear in any mesh fact or
RPC response** — it's exactly the kind of internal-only field the privacy
boundary (spec §2) depends on not leaking. Flag this explicitly in the
eventual `evoq_projection`/emitter code: the field exists in the aggregate's
own event but is deliberately dropped when building any integration fact.

`record_video_clip_view` is dispatched from **inside the streaming desk's own
callback** (§5.2), not from an API handler and not from a policy reacting to
another domain event — it's a third, uncontroversial dispatch site: an SDK
callback building and dispatching a command, mechanically identical to what
an API handler does. No new naming category needed.

Live viewership (concurrent viewers of an in-progress broadcast, before any
clip exists) is a different, ephemeral metric than clip view count and isn't
in spec scope — noted in §9.6, not designed here.

---

## 3. Live → Clip: a Policy, not a "process manager"

The plan doc's own language calls this "the live→clip process manager."
That's imprecise: `Channel` and `VideoClip` live in the **same** CMD app
(`guide_tube_lifecycle`), the same evoq store. Per
`NAMING_CONVENTIONS.md`'s Policy-vs-Listener table, a same-division reaction
to an internal event dispatching a command to another local aggregate is a
**Policy**, not a Process Manager (PMs are reserved for cross-division /
external-fact triggers — see §6 for the one place this repo actually needs
a real PM).

**Module:** `on_live_session_ended_maybe_upload_video_clip` — sibling slice
under `guide_tube_lifecycle/src/`, own supervisor, own gen_server, `evoq_event_handler`
behaviour (not a raw gen_server — Demon #39).

```
interested_in() -> [<<"live_session_ended_v1">>].

handle_event(<<"live_session_ended_v1">>, Event, _Meta, State) ->
    #{channel_id := ChId, session_id := SId, recording_ref := Ref,
      started_at_label := Label} = data(Event),   %% whatever fields it needs, all FROM the event
    Cmd = upload_video_clip_v1:new(#{
        channel_id => ChId, local_ref => Ref,
        name => default_clip_name(Label),          %% see 9.4 — no rename desk exists yet
        description => <<>>, tags => [], thumbnail_mcid => undefined,
        source => <<"recorded">>
    }),
    dispatch(Cmd),
    %% If §8's resolution of open question 4 is ever flipped to
    %% "auto-publish", a second dispatch of publish_video_clip_v1 goes
    %% here, chained. Resolution below keeps this a single dispatch.
    {ok, State}.
```

Every field the policy needs (`recording_ref` above all) must already be on
the event — this is DDD.md's Chain of Responsibility, walked backward: the
policy needs `recording_ref` → the event must carry it → the handler must
echo it from the command → the `end_live` command must be enriched with it at
the boundary. See §9.3 — this chain currently has no source for
`recording_ref` at all.

---

## 4. Integration facts — what leaves the edge node, and the topic-namespace problem

### 4.1 The problem the plan doc's mapping glossed over

The plan's "Revised primitive-pair mapping" table says PubSub carries
"integration facts... published by hecate-tube, consumed by the macula-realm
`tube` aggregator" — true, but it silently assumes a shared, known topic the
way hecate-mpong-bot's bots do. mpong-bot's bots all publish under one
**hardcoded** namespace (`hecate_topics`'s `?ORG = <<"beam-campus">>`, `?APP
= <<"hecate">>`) because they're a closed fleet that agreed on it at compile
time. **hecate-tube is not that.** It's a template any owner deploys with
their own identity — there is no fixed org namespace shared across
instances, and the org-namespaced addressing capability (macula ~> 8.6+,
Slice 7c, per this repo's own recent commits) exists precisely to let each
instance address mesh calls *to itself* under its own namespace. That
capability solves the wrong half of this problem: it helps a caller who
*already knows which channel it wants* reach it; it does nothing for a
realm catalog that doesn't yet know any channels exist.

**Resolution (folded forward from §9.1):** catalog-discovery facts ride a
**single fixed, org-independent rendezvous topic baked into every
hecate-tube release** — not a per-owner-namespaced one. Direct RPC/streaming
calls to an *already-discovered* channel use the org-namespaced addressing
as designed. Two different jobs, two different addressing schemes:

| Concern | Addressing | Why |
|---|---|---|
| "does this channel exist at all" | one fixed topic, same across every deployment | realm can't subscribe to a topic it doesn't know the name of |
| "call this specific known channel" | org-namespaced (Slice 7c) | caller already resolved *which* channel; wants to reach *that one* |

### 4.2 Facts and their topics

Fixed topic constants (analogous to `hecate_topics`, but domain-fixed, not
org-fixed — every hecate-tube release ships identical constants):

```
Realm: io.macula   Org: tube-commons   App: tube   (all THREE fixed, not owner-configurable)
```

| Fact | Topic | Published on |
|---|---|---|
| `tube.channel_announced_v1` | `io.macula/tube-commons/tube/channel_announced_v1` | `channel_initiated_v1`, `channel_reconfigured_v1`, `channel_went_live_v1`, `live_session_ended_v1`, **and every 60s regardless of change** (heartbeat) |
| `tube.video_clip_published_v1` | `io.macula/tube-commons/tube/video_clip_published_v1` | `video_clip_published_v1` |
| `tube.video_clip_retracted_v1` | `io.macula/tube-commons/tube/video_clip_retracted_v1` | `video_clip_retracted_v1`, `video_clip_archived_v1` |

`channel_announced_v1` stays one topic per aggregate with an `action`
field disambiguating — it's a snapshot republished on a timer as much
as on a write (heartbeat), so collapsing is the right call there, same
as `advertise_game`'s `action` field elsewhere in this workspace.

`video_clip` facts went the other way (revised PART2 §16): **two topics, no
`action` field**, one per real outcome for a catalog consumer —
`published` (visible) and `retracted` (not visible). `archived` folds
into the `retracted` topic: it's a hecate-tube-local terminal state
(permanent removal from every local query, "delete" being taboo) and
the mesh has no use for the distinction between "temporarily
unpublished" and "gone for good" — both mean the same thing to a
catalog. An `action`-tagged single topic here would have hidden the
real business verb inside the payload instead of the topic name,
exactly the CRUD-adjacent smell the naming rules exist to catch —
there's no topic-explosion risk to avoid (no IDs in the topic, and
only ever three fixed lifecycle outcomes), so there was no reason to
pay that cost.

**Heartbeat, not fire-once.** Demon #45 ("Fire-Once Publishing Over
Unreliable Transport") is a real, previously-burned bug in this exact
workspace. mpong-bot's `discover_games:reannounce/1` (every 2s, tied to a
fast-moving game) is the proven fix pattern; hecate-tube's channel state
changes far more slowly, so 60s is the right interval — a fresh realm-catalog
subscriber is fully converged within one heartbeat window, and channels that
go offline without a clean `end_live` are still detectable (see §7's sweep).

### 4.3 Fact payload shape

`channel_announced_v1` (heartbeat + every write): `channel_id, action
(<<"initiated">>|<<"reconfigured">>|<<"went_live">>|<<"live_ended">>|<<"heartbeat">>),
name, description, owner, tags, logo_mcid, is_live, live_session_id
(nullable), published_clip_count, announced_at`.

`video_clip_published_v1` / `video_clip_retracted_v1` (revised PART2 §16, no
`action` field — the topic name is the action): `clip_id, channel_id,
name, description, tags, thumbnail_mcid, sent_at`. **View count is
deliberately NOT in this fact** — see §4.4 and the resolution of open
question 2 in §8.2.

`local_ref` never appears in either payload (§2.2). `session_id` appears
only inside `channel_announced_v1`, never as its own top-level fact — a
session is a Channel-scoped concept, not an aggregate of its own.

### 4.4 Why view count is RPC-pulled, not PubSub-pushed

A view happens far more often than a configuration change and is far less
urgent to propagate — pushing it either floods the fixed rendezvous topic
(bad for every OTHER channel's discoverability messages sharing it) or forces
throttling logic to be invented (mpong's `tick rem 5` pattern exists
*because* per-tick push doesn't scale; view counts have the same shape).
Instead: hecate-tube counts views itself (§2.2's `record_video_clip_view`,
fired from its own streaming provider's `handle_open/2` — it is uniquely
positioned to know a stream genuinely opened, more truthful than the realm
knowing someone clicked a link) and the realm-side `VideoLive` fetches the
current count **on demand**, once, when a viewer opens a clip's detail page,
via the RPC lookup in §5.3. This is the "revised primitive-pair mapping"
table's own stated purpose for RPC ("a consumer or the realm aggregator
asking a specific channel for a clip's full metadata on demand") — using it
for exactly that, and only that, keeps the fixed rendezvous topic's traffic
proportional to catalog changes, not to viewer traffic.

---

## 5. Primitive wiring, desk by desk

This is the part the whole project exists to prove out — all four primitive
pairs, each with a real provider AND a real consumer.

### 5.1 PubSub (provider: hecate-tube; consumer: macula-realm)

Emitters in `guide_tube_lifecycle` (evoq_event_handler behaviour, per Demon
#39 — not raw gen_servers) — this governs how they learn a fact needs
publishing. **The publish itself goes through `macula_publisher:start_link/5,6`**
(§0.5 — never bare `macula:publish/4,5`), so each publish gets its own
supervised, cancellable pid and its own `pubsub.publish_started_v1`/
`_completed_v1` mesh fact for free:

- `channel_announced_v1_to_mesh` — subscribes to all four channel events
  (`interested_in/0` returns all four types), builds the fact from event
  data, calls `macula_publisher:start_link(channel_announced_publisher, Pool,
  Realm, Topic, Fact, self())` to the fixed topic. Also owns a
  `send_after`-driven heartbeat timer (mirrors `discover_games`'s
  `schedule/2` pattern) that re-publishes the current channel snapshot every
  60s regardless of new events, the same way — this means it needs read
  access to *current* aggregate state for the heartbeat tick, which is the
  one place in this whole design where reading current state from OUTSIDE
  the event flow is correct: a heartbeat isn't reacting to an event, it's a
  timer-driven snapshot publish, so Demon #41 doesn't apply (nothing here
  makes a business decision based on read-model staleness).
- `video_clip_lifecycle_to_mesh` — subscribes to the three clip
  lifecycle events, same `macula_publisher:start_link/5,6` pattern, but
  publishes to one of two fixed topics (`published`/`retracted`), not one
  shared `announced` topic — see PART2 §16. Further split in PART2 §16.2
  into three single-event PMs (`on_video_clip_published_publish_clip`,
  `on_video_clip_retracted_withdraw_clip`,
  `on_video_clip_archived_withdraw_clip`) — this bullet describes the
  storm-time design, PART2 has the as-built shape.

### 5.2 Streaming (provider: hecate-tube; consumer: macula-realm's playback proxy, or any mesh client)

Both live in `query_tube` (byte-serving is a read concern, not a write
concern — see the `stream_mpong_game` precedent, which is a QRY desk even
though it's not `get_*`-shaped).

- `stream_video_clip_by_id` — `macula_streamer:advertise_direct/6,7` under
  procedure `tube.watch_video_clip`, `server_stream` mode. `handle_open/2`
  receives `#{clip_id := Id}`, looks up the clip via `project_tube_store`;
  if `PUBLISHED`, opens `local_ref` and pushes chunks via
  `macula_streamer:send/2` until EOF, then dispatches
  `record_video_clip_view_v1` (§2.2) before `close/1`. Advertised once at
  boot (one procedure serves every clip on this channel, `clip_id` is a call
  argument, not baked into the procedure name). **Refusing an unpublished
  clip is a real, verified gap in the wrapper, not designed away here** —
  see §12: `handle_open/2` has no raw stream pid to call `macula_stream:
  abort/3` on directly, and returning `{stop, Reason, State}` strands the
  caller with no signal at all (the underlying stream is never linked, so
  `terminate/2`'s abort-on-non-normal-stop path never runs either). The
  known escape hatch — accept via `{ok, State}`, capture `self()` before
  spawning a tiny helper process that calls `macula_streamer:close/1` on it
  moments later — avoids the gen_server self-call-during-init deadlock
  (Demon #35) but is a workaround, not a wrapper-native "reject" path.
- `stream_live_channel_by_id` — same wrapper, procedure `tube.watch_live_channel`,
  `handle_open/2` receives `#{channel_id := Id}`, refuses unless `?CHANNEL_LIVE`
  set, otherwise feeds from the live ingest source (see §9.3 — this is the
  same missing piece `recording_ref` depends on: whatever produces the live
  feed bytes for viewers is also what should be recording them to disk).

Both use `advertise_direct` specifically (not plain `advertise`) so a
consumer can direct-dial via DHT resolution instead of needing to already
share a pool link with this exact station — the realistic case for a
mesh-wide audience of strangers, not a small closed pool like mpong-bot's
bot fleet.

### 5.3 RPC (provider: hecate-tube; consumer: macula-realm, or any mesh client)

Both in `query_tube`, via **`macula_response:advertise_direct/6,7`** — not
plain `advertise/5,6`. Correction from the first pass: direct-dial isn't a
latency optimization reserved for streaming, it's the *reachability*
mechanism — `advertise/5,6`'s own moduledoc is explicit that a plain
advertise depends on "advertise-gossip" already having propagated a route
between the caller's station and this one, which a mesh-wide stranger
(the realm, or any consumer that isn't already pooled with this exact
channel's station) cannot assume. Every hecate-tube provider desk needs
`advertise_direct`, RPC included, for the same reason Streaming does:

- `advertise_channel_lookup` — procedure named per the org-namespaced
  addressing convention (this channel's own reachable identity, resolved
  by whoever already knows about it from a `channel_announced_v1` fact).
  `handle_request/2` returns the full current channel snapshot + published
  clip summaries. Exists for on-demand refresh when a viewer opens a channel
  page — the heartbeat fact already carries most of this, so this closes
  the gap only when the realm's cache is suspected stale.
- `advertise_video_clip_lookup` — `handle_request/2` receives `#{clip_id}`,
  returns clip metadata **including current view count**, only for
  `PUBLISHED` clips (else `{error, not_found, State}` — never confirm the
  existence of an unpublished or archived clip over RPC, same privacy
  discipline as the streaming desks).

Both need the service's stable `Identity :: macula_identity:key_pair()` for
`advertise_direct`'s signing argument, on top of `{Pool, Realm}` — see §0.5
and §12.

### 5.4 Content (provider: hecate-tube; consumer: anyone holding the MCID)

Put side — **`macula_feeder:start_link/4,5`** (plain, not direct: a PUT just
needs to land in *some* reachable content store; chunked content's
`content_announcement` DHT record makes it discoverable mesh-wide
automatically afterward, so there's nothing to direct-dial *to* yet).
Called inline at the point a logo or thumbnail is captured (inside the
`initiate_channel`/`reconfigure_channel` API handler for logos, inside the
`upload_video_clip` API handler for thumbnails); the callback module's
`handle_fed/2` receives `{ok, Mcid} | {error, _}` and the command carries
whichever it got as `logo_mcid`/`thumbnail_mcid`.

Get side — consumers (the realm, a viewer's browser via a thin proxy) use
**`macula_download:start_link_direct/4,5`**, which resolves the MCID's
provider from its `content_announcement` automatically — no station
argument needed, unlike the put side. No channel-specific procedure exists
for this, unlike RPC/Streaming — content addressing needs none.

### 5.5 Summary — all four primitives, both directions, closing the survey's confirmed gap

| Primitive | hecate-tube role (module) | macula-realm role (module) |
|---|---|---|
| PubSub | provider — `macula_publisher` via `channel_announced_v1_to_mesh`, `video_clip_lifecycle_to_mesh` | consumer — `macula_subscriber` via `Tube.Subscriber` (§7) |
| Streaming | provider — `macula_streamer:advertise_direct` via `stream_video_clip_by_id`, `stream_live_channel_by_id` | consumer — `macula_stream_sink:start_link_direct` via the playback proxy (§7.3) |
| RPC | provider — `macula_response:advertise_direct` via `advertise_channel_lookup`, `advertise_video_clip_lookup` | consumer — `macula_direct_dial:call/6` (not the async wrapper — see §0.5) via `Tube.RemoteLookup` (§7) |
| Content | provider (put) — `macula_feeder:start_link` inline at configure/upload | consumer (get) — `macula_download:start_link_direct` via the playback proxy / thumbnail rendering |

This is the first service in the workspace where hecate-om's RPC wrapper
actually needs a wired **responder**, not just DHT discovery — directly
closing the gap `PLAN_MACULA_API_INTEGRATION_SURVEY.md` confirmed. It's also
the first real exercise of PubSub, Content, and Streaming at the hecate-om
substrate layer at all — that survey explicitly deferred all three "pending
a real DIY need." See §11-§12.

---

## 6. The one genuine cross-division Process Manager in this design

Everything above is intra-division (Policy) or edge-to-realm (facts/RPC/
streaming, not PM-shaped — the realm has no local aggregate to dispatch
commands into, see §7). There is exactly one place a real PM pattern
applies: **none, currently** — hecate-tube's two aggregates only talk to
each other via the Policy in §3, and the realm side is pure read-model
materialization (§7), not command dispatch. Noted here explicitly so a
future reader doesn't go looking for a PM that this domain doesn't need.

(Revised in the crafting session — PART2 §16.2 adds three real PMs after
all, but they're mesh-facing, not cross-division in the sense this section
meant: hecate-tube has no second local CMD app to be a PM's target. The "no
PM" conclusion here was specifically about intra-workspace cross-division
dispatch, which still doesn't exist in this design.)

---

## 7. macula-realm side: `tube`/`tube_web` — corrected shape

### 7.1 Finding: no CMD app, and the plan's `tube`/`tube_web` app split doesn't match this umbrella's real precedent

The plan doc's proposed shape (new sibling apps `tube`, `tube_web`,
mirroring `macula_realm`/`macula_realm_web`) reasons from **naming**
symmetry. Reading the umbrella's *actual* structure for its one other
mesh-consuming feature (Mpong) shows a different, already-proven pattern:
Mpong has **no** `mpong`/`mpong_web` sibling apps at all.
`MaculaRealm.Mpong`, `MaculaRealm.Mpong.Subscriber`, and
`MaculaRealmWeb.MpongLive` all live inside the umbrella's one shared domain
app and one shared web app. Precedent beats a naming-symmetry guess:

> **`tube` and `tube_web` are not new OTP apps.** The mesh-subscribing glue
> and LiveViews live inside the existing `macula_realm` / `macula_realm_web`
> apps as `MaculaRealm.Tube.*` / `MaculaRealmWeb.TubeLive` /
> `MaculaRealmWeb.VideoLive`, exactly where Mpong's equivalents live today.

**`project_tube_catalog` and `query_tube_catalog` DO earn their own OTP
apps**, unlike Mpong's ad hoc ETS cache — this domain has real, durable,
growing read models (Ecto-backed, paged queries, two related tables) of the
same shape `project_realm`/`query_realm` already have, and the whole reason
this project exists is to do the pattern *properly* rather than repeat
Mpong's informal shortcut. Mpong is real prior art for *how a mesh subscriber
works here*; it is not the template for *where durable read models belong*.

(Revised, PART2 §16: `tube` ended up as its own new sibling OTP app after
all, not folded into `macula_realm` — see the top-of-file correction note
in ROOT and PART2 §16 for the as-built shape. `tube_web` stayed as
described here: no new app, `MaculaRealmWeb.Tube.*` module namespace inside
the existing `macula_realm_web`.)

### 7.2 No CMD app — why

The realm never makes a business decision about a channel or a clip; it only
observes facts a hecate-tube instance already decided to publish. There is
no local aggregate whose business rules would need enforcing, so there is
nothing for a CMD department to guard. This is the flow-type distinction in
`NAMING_CONVENTIONS.md`'s event-flow table: flows 1-3 (projection, pg
emitter, mesh emitter) all apply to *this* domain's own events; flow 5
(Listener → dispatches a command) applies when an external fact needs to
trigger a *local business decision*. Materializing a read model from an
external fact with no local decision to make doesn't fit flow 5 — it's flow
1, just sourced from mesh instead of evoq/pg. `INTEGRATION_TRANSPORTS.md`'s
PRJ Desk Structure section already describes exactly this shape (`on_{event}_from_{transport}_project_to_{storage}_{target}`,
living in the PRJ app, calling a projection directly) — transport here is
`mesh` instead of `pg`, otherwise unchanged.

### 7.3 Concrete module list

**This sketch predates the actual build and diverged from it — see PART2
§16 for the real, live-verified module list and don't take the filenames
below as current.**

```
apps/project_tube_catalog/lib/project_tube_catalog/
  channel.ex                                          (Ecto schema: channels table)
  video_clip.ex                                        (Ecto schema: video_clips table)
  on_tube_channel_announced_v1_from_mesh_project_to_ecto_channels.ex
  on_tube_video_clip_announced_v1_from_mesh_project_to_ecto_video_clips.ex

apps/query_tube_catalog/lib/query_tube_catalog.ex
  get_channels_page/1, get_channel_by_id/1
  get_video_clips_page/2 (by channel_id), get_video_clip_by_id/1
  refresh_video_clip_view_count/1   -- calls MaculaRealm.Tube.RemoteLookup, falls back to cached count

apps/macula_realm/lib/macula_realm/tube/
  subscriber.ex          (MaculaRealm.Tube.Subscriber -- @behaviour :macula_subscriber,
                          started via :macula_subscriber.start_link/5,6 -- NOT a hand-rolled
                          subscribe + handle_info the way mpong_subscriber.ex does; see below)
  remote_lookup.ex        (MaculaRealm.Tube.RemoteLookup -- :macula_direct_dial.call/6,
                          synchronous, same precedent as hecate_om_capabilities:call_capability/4 -- see §0.5)

apps/macula_realm_web/lib/macula_realm_web/live/
  tube_live.ex            (channel grid + per-channel clip grid, live-updates via Phoenix.PubSub)
  video_live.ex           (single clip or live playback, own route -- see 9.5 for the shareable-URL rationale)

apps/macula_realm_web/lib/macula_realm_web/controllers/
  tube_stream_controller.ex   (plain Plug controller, NOT a LiveView -- see 9.5)
```

`MaculaRealm.Tube.Subscriber` implements `@behaviour :macula_subscriber`
directly (`init/1`, `handle_event/4`) and is started via
`:macula_subscriber.start_link(MaculaRealm.Tube.Subscriber, pool, realm,
topic, args)` — one subscriber process per fixed topic from §4.2, not one
per owner. This is a deliberate departure from `mpong_subscriber.ex`'s own
hand-rolled `:macula.subscribe/4` + raw `handle_info({:macula_event, ...})`
clauses: Mpong predates (or never adopted) the supervised-wrapper
convention documented in §0.5, and per macula-io's own "no Elixir wrappers
for Erlang" rule, implementing the real Erlang behaviour directly in an
Elixir module — not hand-rolling the raw subscribe/receive loop it already
replaces — is the correct, idiomatic call here. `handle_event/4` routes to
`ProjectTubeCatalog`'s upsert functions and reuses `MaculaRealm.Mesh.handle/0`'s
already-shared pool (Demon #2 — don't stand up parallel mesh infrastructure).

### 7.4 Staleness handling

Unlike Mpong's ephemeral game rows (evicted outright), a channel is a
persistent identity — a temporarily-offline channel's past clips should
stay visible (VOD doesn't need the channel live, just reachable when a
viewer presses play). So: `channels` gets a `last_seen_at` + computed
`online?` (no heartbeat within 3× the 60s interval = offline), sweep marks
rather than deletes. `video_clips` rows are never swept by staleness at all
— only the three lifecycle facts (published/retracted/archived) touch them,
and `retracted`/`archived` already remove them from the public catalog by
the same upsert path (set a `visible` flag, or delete the row — since this
is a rebuildable read model either is fine; deleting is simpler and there's
no requirement to show retracted clips anywhere in the realm catalog).

---

## 8. Resolutions — the six SPECIFICATION §6 questions

### 8.1 Q1 — Owner UI tech

**Recommendation: plain cowboy-rendered HTML, htmx for the interactive bits
(publish/retract toggles, live status).** No counter-evidence surfaced during
this storm to change the spec's own tentative answer — Erlang genuinely has
no LiveView equivalent, and none of the desks designed above need anything
richer than form posts + partial re-renders. Confirmed, not reopened.

(As-built, PART2 §15: no htmx after all — plain full-page POST+redirect,
htmx couldn't be vendored without an external fetch this repo's
self-hosted conventions avoid.)

### 8.2 Q2 — View counting: who counts, who propagates

**Recommendation: hecate-tube counts (its streaming provider is the only
component that knows a stream genuinely opened); the realm never counts
independently.** Propagation is RPC-pull-on-demand (§4.4), not PubSub-push —
this is a refinement beyond the spec's original either/or framing, driven by
noticing during the storm that per-view push facts would flood the one fixed
rendezvous topic every other channel's discoverability messages share.

### 8.3 Q3 — Peer-to-peer follow

**Recommendation: drop it.** Spec §7 frames discovery as exclusively
through the realm catalog; "follow another channel" appears nowhere in the
confirmed spec text, only in the plan doc's own speculative design section
and in Phase 0's `channel_state.erl` (`following :: sets:set(binary())`,
never wired to any desk). That field is unused scaffolding, not evidence of
a real requirement — remove it along with the `sets` import in the crafting
session. If a real reason for peer-to-peer follow surfaces later, it's a
clean addition (a new desk, no rework), not a retrofit.

### 8.4 Q4 — Live → clip: published or private by default

**Recommendation: private by default.** The spec's own framing (§2, phrased
as an unqualified general principle: "Video clips remain on the edge node
and are not disclosed to the mesh unless the owner explicitly publishes
them") reads as a design commitment, not a fact scoped only to uploads. A
recording auto-publishing without review also has real failure modes a
product like this should protect against by default (a technical glitch, a
moment during the stream the owner wouldn't have wanted permanently public)
that "publish is a deliberate, separate act" specifically guards against.
Counter-consideration, for the record: a stream that was public while live
"suddenly" going private at end-of-session may surprise some owners — if
that's the wrong call, the fix is one line (the Policy in §3 dispatches a
second `publish_video_clip_v1` right after upload), not a redesign.

### 8.5 Q5 — Channel↔clip relationship

**Recommendation: separate aggregates (as modeled throughout §1-§2), association
built on the read side.** Rationale: (a) evoq/reckon-db's grain is
"aggregate = independent stream" — embedding a growing clip list in
`channel_state` means every clip mutation serializes through the channel's
one gen_server and every clip event bloats the channel's own stream with
data a channel-level business rule never needs to reason about; (b) clip
lifecycle (`UPLOADED`/`PUBLISHED`/`ARCHIVED`) is a real per-clip state
machine that deserves its own bit-flag status header, not a flag buried in
an array element; (c) real precedent in this exact workspace does the same
thing — realm memberships, capabilities, and orders are all separate streams
from their "owner" aggregate, with the read side doing the joining (this is
literally what PRJ departments are *for* — DDD.md's "index cards"). The
"channel's clip library" the spec asks for is `get_video_clips_page(channel_id)`
in `query_tube` (§2), not a field on `channel_state`.

### 8.6 Q6 — Naming the permanent-removal desk

**Recommendation: `archive_video_clip_v1` → `video_clip_archived_v1`.**
Of the candidates offered (`discard`, `retire`, `remove`), none is actually
needed — Hecate already has a standard word for exactly this state
(terminal, hidden from queries, event history preserved rather than erased,
since event sourcing never truly deletes): **"archived,"** used identically
across domain/division/plugin lifecycles throughout this codebase
(`NAMING_CONVENTIONS.md`'s own Event Verb table: "Soft delete →
`{noun}_archived_v1`, NOT `{noun}_deleted_v1`"). This isn't a new choice
being introduced for this domain — it's applying the existing convention
instead of picking a new synonym.

---

## 9. What the storm surfaced beyond the six listed questions

### 9.1 Catalog discovery needs a fixed rendezvous topic, not per-owner namespacing

Covered in full in §4.1 — the plan's original primitive-pair mapping didn't
address how the realm learns which channels exist in the first place. Fixed
`io.macula/tube-commons/tube/*` topics, baked into every release, resolve
it using a pattern (heartbeat re-publish) already proven in this workspace
rather than inventing a new DHT record type.

### 9.2 `tube`/`tube_web` as new OTP apps doesn't match this umbrella's real precedent

Covered in full in §7.1 — Mpong's actual placement (inside `macula_realm` /
`macula_realm_web`) is the demonstrated convention; the plan's naming-driven
guess should yield to it for the glue/LiveView layer, while PRJ/QRY still
earn their own apps. (Revised again since — see §7.1's own update note.)

### 9.3 The live-ingest input side is completely unspecified — and it's load-bearing

Neither the spec nor the plan says how bytes get **into** hecate-tube during
a live broadcast (camera/OBS/RTMP-in/something else), or what records those
bytes to disk so `end_live_v1` can carry a `recording_ref`
(§1.3, §3). Every part of the live→clip flow this storm designed depends on
that reference existing. **This needs its own small design pass before the
crafting session can build `go_live`/`end_live`/the Policy/`stream_live_channel_by_id`
for real** — it's not resolvable by inference from the spec as given, so
it isn't resolved here; flagging it as the single highest-priority gap this
storm found.

### 9.4 No desk exists to rename/redescribe an auto-minted clip

The Policy in §3 mints a clip with a default generated name and empty
description/tags (spec §4's desk list doesn't include "edit clip metadata,"
so none was added — respecting "don't add unrequested features"). But this
means every clip born from a live session keeps a machine-generated name
forever unless a future session adds an amend desk. Flagging as a real,
likely-wanted gap rather than silently adding the desk now.

### 9.5 VOD seeking may not be deliverable with the streaming primitive as documented

`STREAMING_GUIDE.md` describes content streaming as open-ended, push-from-
start, no fixed size — exactly right for a live broadcast (no seeking
expected), but HTML5 `<video>` scrubbing wants byte-range requests against a
resource of known length. `tube_stream_controller.ex` (§7.3) can pipe an
open-ended mesh stream into a chunked HTTP response today, giving
play-through-once VOD viewing, but **full scrub/seek on a stored clip is not
designed here** — it would need either a range-aware extension to the
streaming primitive (a macula SDK change, out of this repo's scope) or a
fallback path outside "streamed, not downloaded" for seek specifically. This
is why `VideoLive` gets its own route (§7.3) rather than being folded into
`TubeLive` — deep-linkable, shareable single-clip URLs are a reasonable,
spec-consistent inference ("YouTube-like") even though the spec's §7 only
floated the split as undecided, and are needed regardless of how the seek
question resolves.

### 9.6 Live concurrent-viewer count is a different, unspecified metric

Noted in §2.2 — spec's "number of views" is clip metadata, which only exists
once a clip does. A live broadcast's concurrent-viewer count (if wanted at
all) would be ephemeral Channel-scoped state, not designed here since
nothing in the spec asks for it.
