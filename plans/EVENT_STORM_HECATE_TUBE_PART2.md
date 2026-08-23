## 11. hecate-om today: what it wraps, what it doesn't, what hecate-tube newly exercises

Grounded in reading `hecate-om/src/hecate_om.erl`, `hecate_om_capabilities.erl`,
`hecate_om_service.erl` in full, plus `PLAN_MACULA_API_INTEGRATION_SURVEY.md`
(hecate-om's own prior audit, done the day before this storm).

| Primitive pair | hecate-om today | What hecate-tube needs |
|---|---|---|
| RPC consumer | **Done** — `hecate_om:call_capability/4` → `hecate_om_capabilities:call_capability/5,7`: hand-rolled resolve→verify→dial→failover, deliberately not built on `macula_request:start_link_direct` (sync semantics + multi-provider failover the async wrapper doesn't give you for free) | None — every hecate-tube RPC need in this design is provider-side (§5.3, PART1). Nothing in this design calls another service's RPC. |
| RPC provider | **The confirmed gap.** `hecate_om_capabilities.erl` writes `procedure_advertisement` DHT records (discovery) via `macula:put_record/2`, but never calls `macula:advertise/5` or `macula_response:advertise_direct/6,7` anywhere in the codebase — a service is discoverable but not callable | `advertise_channel_lookup`, `advertise_video_clip_lookup` (PART1 §5.3) — hecate-tube calls `macula_response:advertise_direct/6,7` directly, since hecate-om has nothing to call yet |
| PubSub | **Zero wrapping** — no `hecate_om:subscribe`, no `hecate_om:publish`. Explicitly deferred by the survey "pending a real DIY need" | `channel_announced_v1_to_mesh`, `video_clip_lifecycle_to_mesh` (PART1 §5.1) via `macula_publisher` directly |
| Content | **Zero wrapping.** Same deferral | Logo/thumbnail put+get (PART1 §5.4) via `macula_feeder`/`macula_download` directly |
| Streaming | **Zero wrapping.** Same deferral | `stream_video_clip_by_id`, `stream_live_channel_by_id` (PART1 §5.2) via `macula_streamer`/`macula_stream_sink` directly |

**The pool/identity substrate hecate-tube DOES inherit from hecate-om,
unchanged:** `hecate_om_identity` (a gen_server, not exported past
`hecate_om:macula_client/0` and `hecate_om:service_cert/0`) already connects
once at boot, reattaches on pool death, and holds `{Pool, Realm, KeyPair,
Org}` — hecate-tube's own provider desks don't need their own connection
lifecycle, only a way to reach all four of those values, which the current
public facade only partially exposes (see §12).

hecate-tube is, concretely, the first service in this workspace exercising
the provider half of RPC and all of PubSub/Content/Streaming at the
hecate-om substrate layer — exactly the "real DIY need" the survey said to
wait for before designing those wrappers. §12 is the running, evidence-based
version of what that survey's own recommended design (`hecate_om_pubsub`,
the `hecate_om_capabilities` provider extension, `mesh_handles/0`) should
account for once it's written for real.

---

## 12. hecate-om / macula-SDK findings log (seed for the eventual wrapper plan)

Not a design — a running list of concrete friction found while designing
hecate-tube's real desks against the real wrapper source, kept separate from
speculation. Each entry names the desk that surfaced it.

1. **Direct-dial providers need a keypair, not just `{Pool, Realm}`.**
   `macula_response:advertise_direct/6,7`, `macula_streamer:advertise_direct/6,7`,
   and (for a specifically-targeted put) `macula_feeder:start_link_direct/5,6`
   all take `Identity :: macula_identity:key_pair()`. The survey's own
   recommended `hecate_om:mesh_handles/0 -> {ok, Pool, Realm}` doesn't cover
   this — it needs to return the keypair too (or hecate-om needs a fourth
   accessor), or every direct-dial provider desk in hecate-tube (`advertise_channel_lookup`,
   `advertise_video_clip_lookup`, `stream_video_clip_by_id`,
   `stream_live_channel_by_id`) has to reach past the public facade into
   `hecate_om_identity:keypair/0` directly, exactly the pattern the survey
   already flagged as a problem for `realm/0` in its Question 4. *Surfaced
   by: PART1 §5.2, §5.3.*

2. **`macula_streamer:handle_open/2` has no clean immediate-rejection path.**
   The callback receives no raw stream pid (only its own wrapper `self()`,
   which supports `send/2,3`/`close/1` but calling either from inside
   `handle_open/2` — which runs inside the wrapper's own `init/1` — is a
   gen_server self-call during init and deadlocks, Demon #35). Returning
   `{stop, Reason, State}` doesn't help either: `open/7` never links the
   stream or reaches `terminate/2`'s abort-on-non-normal-stop path on that
   branch, so the caller is simply stranded until their own `recv` timeout
   (30s default) — no `STREAM_ERROR` abort is ever sent. The only working
   escape hatch found: accept via `{ok, State}`, capture `self()` in a
   variable, and spawn a short-lived helper process that calls
   `macula_streamer:close/1` on the captured pid moments later. This is a
   macula-SDK-level gap (not hecate-om's to fix), but it blocks
   `stream_video_clip_by_id`/`stream_live_channel_by_id`'s "refuse an
   unpublished clip / a not-live channel" requirement as designed — worth
   raising with macula directly, not working around silently. *Surfaced by:
   PART1 §5.2.*

3. **A synchronous RPC consumer has a real, precedented reason to skip the
   wrapper.** `macula_request`'s `start_link`/`handle_reply/2` is async by
   design; a query-shaped call site (`Tube.RemoteLookup`, called from inside
   a Phoenix context function that must return a value, not receive one
   later) doesn't fit that shape any better than `hecate_om_capabilities:call_capability/4`
   did — which is why `call_capability` itself calls `macula:call_station/6,7`
   directly rather than `macula_request:start_link_direct`. Worth stating as
   a *named, recognized pattern* (synchronous query-site → raw direct-dial
   call) rather than re-discovering it as an ad hoc exception every time.
   *Surfaced by: PART1 §7.3.*

4. **PubSub, Content, and Streaming are no longer "no DIY need yet."** The
   survey's recommendation to defer all three was explicitly conditional on
   that absence. hecate-tube's `channel_announced_v1_to_mesh` (PART1 §5.1),
   logo/thumbnail put+get (PART1 §5.4), and both streaming provider desks
   (PART1 §5.2) are three concrete, real, non-hypothetical consumers now.
   Whoever writes `PLAN_HECATE_OM_MESH_WRAPPERS.md` should treat PART1 §5 as
   the requirements input the survey said didn't exist yet.

*Add to this list as the crafting session writes real code against §5 —
the entries above are from design-time reading of the wrapper source, not
yet from a running implementation; expect more once code exists.*

5. **The §12.2 streamer gap was a plain bug, not a missing capability.**
   `macula_streamer:handle_open/2`'s existing `{stop, Reason, NewState}`
   return is already the domain-agnostic reject path (macula_streamer stays
   completely ignorant of "clips" or "published" either way) — the bug was
   that `open/7` never linked or aborted `StreamPid` on that branch, so the
   peer got silence instead of a signal. Fixed at the source in
   `macula-io/macula` (one function, `abort_rejected_stream/2`, reusing the
   existing `?CANCEL_CODE` abort machinery `terminate/2` already had for the
   crash case). `stream_video_clip_by_id`'s `handle_open/2` just returns
   `{stop, not_found, State}` for an unpublished clip — confirmed via a live
   boot, not just reasoned about.
6. **`evoq_event_handler` gives its callback module no hook for
   non-event messages.** `handle_info/2` lives on `evoq_event_handler`'s own
   gen_server, not delegated to the callback module — a callback module
   can't run a `send_after` heartbeat timer inside itself. Fix: split the
   timer into its own plain `gen_server` (`channel_heartbeat`), sharing a
   pure helper module (`channel_announcement`) with the event-reactive
   emitter rather than trying to make one module do both jobs. Not a
   macula/evoq gap to report anywhere — just a real shape constraint
   worth knowing before reaching for a heartbeat-inside-a-handler design
   again.
7. **A `macula_publisher` callback module and an `evoq_event_handler`
   callback module can't be the same module.** Both behaviours require an
   `init/1` callback with different semantics — one shared, trivial
   fire-and-forget `tube_mesh_publisher` module (matching the SDK's own
   documented example shape) serves every emitter in this app instead.
8. **A repeating re-advertise timer would leak a supervisor per tick.**
   Unlike `hecate_om_capabilities`'s DHT-record republish (idempotent —
   `macula:put_record` just overwrites), `macula_response:advertise_direct`/
   `macula_streamer:advertise_direct` each start a brand-new, unsupervised
   factory supervisor on every call. `tube_mesh_providers` retries the
   *initial* advertise until it succeeds once, then stops — a stale DHT
   record after a pool reconnect is a known, real gap this leaves
   unaddressed, not something to solve by re-advertising on a timer.
9. **Dev-time-only, not an SDK/hecate-om finding:** building against local
   `macula`/`hecate_om` changes before they're hex-published needs
   `_checkouts/` symlinks (`ln -s .../macula _checkouts/macula`, same for
   `hecate_om`) — and a stale non-checkout copy under `_build/default/lib/`
   from an earlier `rebar3 compile` (before the checkout existed) silently
   wins on the code path over the fresh `_build/default/checkouts/` one.
   `rm -rf _build && rebar3 compile` is the reliable fix; `rebar3 clean`
   alone does not touch dependency apps. Cost real time once already this
   session — worth remembering before assuming a checkout is being used
   just because rebar3 logs "is a checkout dependency and cannot be locked."

---

## 13. Punch list against Phase 0 for the next (crafting) session

Concrete, in the order a session would naturally hit them:

1. Rename `initialize_channel`→`initiate_channel` throughout (files, module
   names, command/event types, the `initialized_at`/`org` fields) — PART1 §1.1.
2. Remove `channel_state.erl`'s `following` field and the `sets` import —
   PART1 §8.3.
3. Add `description`, `tags`, `logo_mcid` to `channel_state` /
   `initiate_channel_v1` / `channel_lifecycle_to_channels.erl`'s row shape.
4. Add `reconfigure_channel`, `go_live`, `end_live` desks to
   `guide_tube_lifecycle` per PART1 §1.3.
5. New `tube_video_clip_status.hrl`, `video_clip_aggregate.erl`,
   `video_clip_state.erl`, and the five desks in PART1 §2.2.
6. New Policy `on_live_session_ended_maybe_upload_video_clip` per PART1 §3.
7. New `project_tube` desks for every channel and clip event (PART1 §5.1's
   emitters are separate from these — projections write the local read
   model, emitters publish mesh facts; both subscribe to the same events,
   neither calls the other).
8. New `query_tube` desks: `get_channels_page`, `get_video_clips_page`,
   `get_video_clip_by_id`, plus the four mesh-facing provider desks in
   PART1 §5.2 and §5.3.
9. Resolve PART1 §9.3 (live ingest input) before attempting `go_live`/`end_live`/
   `stream_live_channel_by_id` for real — everything else in this punch
   list can proceed without it.
10. On the macula-realm side: `project_tube_catalog` + `query_tube_catalog`
    as new OTP apps; `MaculaRealm.Tube.*` + `MaculaRealmWeb.TubeLive`/
    `VideoLive`/`TubeStreamController` inside the existing apps — PART1 §7.
11. Every provider/consumer desk in PART1 §5 calls the SDK's supervised wrapper
    module directly (`macula_publisher`, `macula_subscriber`,
    `macula_response`, `macula_request`/`macula_direct_dial`, `macula_feeder`,
    `macula_download`, `macula_streamer`, `macula_stream_sink`) — never
    `hecate_om`, which doesn't wrap any of these yet (§11), and never the
    bare `macula:*` facade function a wrapper already covers (PART1 §0.5). Resolve
    the keypair-access gap (§12.1) before writing the direct-dial provider
    desks — `hecate_om`'s public facade doesn't expose one today.
12. Resolve §12.2 (streaming's unpublished-clip refusal) before finalizing
    `stream_video_clip_by_id`/`stream_live_channel_by_id`'s handler — the
    workaround noted there works but needs deciding on, not discovering
    mid-implementation.

---

## 14. Crafting session status (2026-08-22, MVP-scoped)

**Done, compiled, eunit-green (32/32), and live-boot smoke-tested** (real
CMD→evoq→reckon-db→PRJ→QRY→HTTP path, exactly the Phase 0 verification
recipe, extended to cover both dossiers and the new mesh-provider
processes staying alive):

- Items 1-3, 5, 7, 8, 11 (MVP-applicable parts), 12 — done as designed,
  with the two corrections in §12 items 5-6 above (streamer fix instead
  of workaround; heartbeat as its own process instead of living inside
  the event-handler callback).
- Item 4 (`reconfigure_channel`) — done. `go_live`/`end_live` — **not
  done, deliberately**: the owner cut live broadcast from this MVP pass
  (PART1 §9.3's live-ingest gap stays fully parked, per the top-of-file MVP
  scope note).
- Item 6 (the live→clip Policy) — **not applicable to this MVP**, no
  `live_session_ended_v1` event exists without `go_live`/`end_live`.
- Item 9 (mesh-facing QRY provider desks) — done: `advertise_channel_lookup`,
  `advertise_video_clip_lookup` (RPC), `stream_video_clip_by_id`
  (Streaming), plus the owner's own read routes
  (`get_channels_page`, `get_video_clips_page`, `get_video_clip_by_id`).
  `stream_live_channel_by_id` — not applicable, same live-scope cut.
- Item 10 (macula-realm `tube`/catalog/LiveViews) — **not started.**
- Item 11's Content half (logo/thumbnail put via `macula_feeder`) — **done**,
  see §15 below.

**New, not on the original punch list, added during crafting:**
`tube.video_clip_viewed_v1` mesh fact (own topic, separate from the
catalog rendezvous topic) — see the streamer/view-count corrections
earlier in this file.

---

## 15. Owner-facing web UI + hex/deploy chain (2026-08-22, same day, continued)

**Hex chain closed.** `macula` 10.0.0 and `hecate_om` 0.14.0 are both
published for real. This repo's `rebar.config` moved off the dev-time
`_checkouts/` symlinks (finding 9, now historical) onto `{macula, "~>
10.0"}` / `{hecate_om, "~> 0.14"}` — verified against a genuine fresh hex
fetch (`rebar.lock`'s resolved `pkg` versions checked, not a checkout),
32/32 eunit passing.

**Deployed and mesh-connected.** `github.com/hecate-services/hecate-tube`
now exists (it didn't before), CI green, `ghcr.io/hecate-services/hecate-tube`
public. Running on beam02 via `macula-demo/infrastructure`'s pull-based
reconciler — confirmed live, not just "should work": `/health` green, and
`hecate_om:macula_client()` on the running node returns `{ok, Pid}`, a
genuine attached mesh pool under the `io.macula` realm through
`station-de-frankfurt.macula.io`. `HECATE_REALM` is deliberately
`macula_realm:id(<<"io.macula">>)`'s own tag on every hecate-tube
deployment that wants to show up on the shared catalog later, not a
fleet-internal realm — see the macula-demo commit for the full rationale.

**The owner-facing web UI is built.** Plain cowboy-rendered HTML forms, no
JS/htmx (htmx was always optional per PART1 §8.1's own resolution, and can't be
vendored without an external fetch this repo's self-hosted conventions
avoid anyway) — full-page POST+redirect (PRG), living in the top-level
`hecate_tube` app rather than `query_tube` (whose own name promises a
read-only JSON API). Pages: dashboard (channel card + clip grid),
configure (one form serves both `initiate_channel` and
`reconfigure_channel`), clip upload, publish/retract/archive as pure POST
actions. The video file streams straight to disk
(`cowboy_req:read_part_body/2`'s `{more, Data, Req}` loop, never buffered
whole) via a new shared `tube_multipart` helper; logo/thumbnail images are
small enough to buffer and go through Content via a new synchronous
`macula_feeder`-wrapping helper (`tube_content_put`), degrading to no-op
when the mesh is dark. Every user-supplied field is HTML-escaped on
render (`tube_html:escape/1`) — this app's one deliberate stored-XSS
guard, since owner-typed text round-trips through the owner's own browser
on every page load.

Verified live end to end, not just compiled: booted the real release,
drove the actual endpoints with `curl` (multipart configure, multipart
clip upload with a real file confirmed byte-for-byte on disk, then
publish → retract → archive), confirmed each transition via the JSON read
API.

**What's left, unchanged from §14's own list:** the macula-realm side
(`tube`/catalog/`TubeLive`/`VideoLive`) is the only remaining MVP-scope
item not started. Live broadcast (`go_live`/`end_live`, PART1 §9.3's live-ingest
gap) stays parked, per the owner's own MVP cut.

---

## 16. macula-realm side built + verified live; mesh-fact contract revised

**The macula-realm side is done.** New apps in `macula-io/macula-realm`
(`system/apps/`): `tube` (`Tube.SubscriberStarter`, `Tube.Subscriber`,
`Tube.RemoteLookup`, `Tube.Cbor`), `project_tube_catalog`
(`ProjectTubeCatalog`, Ecto schemas `Channel`/`VideoClip`,
`tube_channels`/`tube_video_clips` migrations under `macula_realm`'s
shared `priv/repo/migrations`, since the umbrella has one `Repo`),
`query_tube_catalog` (thin read API, `refresh_video_clip_view_count/1`
calling `Tube.RemoteLookup` with a cached-count fallback). Web layer in
`macula_realm_web`: `MaculaRealmWeb.Tube.TubeLive` (catalog +
per-channel), `VideoLive` (clip detail), `TubeStreamController` (a
plain Plug, not a LiveView, proxying the Streaming primitive into a
chunked HTTP response a `<video>` tag can play — routes at `/tube`,
`/tube/:channel_id`, `/tube/:channel_id/clips/:clip_id`,
`/tube/stream/:clip_id`).

There is no local aggregate or evoq store behind any of this — the
realm never makes a business decision about a channel or a clip, it
only observes facts hecate-tube already decided to publish, so
`ProjectTubeCatalog` is a plain function called directly by
`Tube.Subscriber`, not an `evoq_event_handler`/PM.

**Verified against the live beam02 deployment, not a synthetic test.**
Local dev `macula_realm` was pointed at the real mesh
(`MACULA_RELAYS=https://station-de-frankfurt.macula.io:4433`) and
watched pick up hecate-tube's real 60s channel heartbeat, and the
owner's own live publish/retract clicks on beam02's dashboard, landing
correctly in `tube_channels`/`tube_video_clips` and rendering on
`/tube` and `/tube/:channel_id`.

### 16.1 Two real bugs found and fixed during that verification

1. **MCIDs are raw binary, not text.** `logo_mcid`/`thumbnail_mcid`
   arrive as the SDK's raw content-address digest (macula has no
   canonical string encoding for an MCID) — Postgres rejected it into
   a `:string` column (`character_not_in_repertoire`), crashing
   `Tube.Subscriber` on every channel heartbeat. Fixed in
   `ProjectTubeCatalog` (`mcid_hex/1`): hex-encode at the
   fact-extraction boundary, both for storage and for future use in a
   URL.
2. **Erlang's `undefined` sentinel crosses the wire as the atom
   `:undefined`, not `nil`.** hecate-tube has no `nil`; an unset
   optional field (e.g. no thumbnail) is `undefined` throughout its
   own state, and that crosses CBOR as-is. This crashed `mcid_hex/1`
   with a `FunctionClauseError` the first time a clip had no
   thumbnail. Fixed centrally in `Tube.Cbor.normalize/1`
   (`normalize(:undefined) -> nil`), not per-field — any optional
   field can carry it, not just MCIDs.

Both confirmed fixed against three live publish/retract cycles from
beam02's actual owner UI, zero crashes.

### 16.2 Mesh-fact contract revised: `video_clip_announced_v1` split, `channel_announced_v1` left as is

Raised in review: overloading one `video_clip_announced_v1` topic with
an `action` field (`published`/`retracted`/`archived`) hides the real
business verb inside the payload instead of the topic name — the
CRUD-adjacent smell the naming rules exist to catch (internally,
`video_clip_state.erl`'s own domain events were already correctly
named `video_clip_published_v1`/`_retracted_v1`/`_archived_v1`; the
mesh fact threw that clarity away). The topic-explosion warning in
this workspace's naming rules is about IDs in topics, not action-types
in topics — there's no explosion risk here, only ever three fixed
lifecycle outcomes.

Also raised: `archived` doesn't need its own mesh signal.
`video_clip_archived_v1` is a hecate-tube-local terminal state
(permanent removal from every *local* query — "delete" is taboo, this
is Hecate's word for it) and the mesh has no use for the distinction
between "temporarily unpublished" and "gone for good"; both mean the
same thing to a catalog consumer.

**Resolution: two mesh topics, not one, not three.**
`tube.video_clip_published_v1` and `tube.video_clip_retracted_v1`, no
`action` field (the topic is the action). `video_clip_archived_v1`
folds into the `retracted` topic — same payload shape, same handler
branch. PART1 §4.3/§7.3's fact tables are corrected to match; treat
any other in-file mention of `video_clip_announced_v1` you find as
stale.

`channel_announced_v1` is deliberately left as a single
action-tagged topic — different in kind, not just degree: the 60s
heartbeat is a timer-driven snapshot republish of the same full-state
shape, not a lifecycle transition, so collapsing it costs nothing a
consumer needs to distinguish.

**Implementation:**
- `video_clip_announced_v1_to_mesh` split into three PMs, not just
  renamed — raised in review: this crosses a real domain boundary (an
  internal domain event causing an external mesh publish), the exact
  case the `on_{source_event}_{action}_{target}` PM convention exists
  to make discoverable at the filesystem level, same justification as
  any cross-domain PM even though there's no target CMD app here, the
  "target" is the mesh itself.

  First pass named all three `..._announce_clip` — caught in review as
  the exact same collapse the wire-fact split had just fixed, one
  layer up: same generic verb on all three again, and "announce" is
  backwards for a removal (you don't announce a retraction, you pull
  the listing). Corrected to two verbs matching what actually happens:
  `on_video_clip_published_publish_clip` (make visible) vs
  `on_video_clip_retracted_withdraw_clip` /
  `on_video_clip_archived_withdraw_clip` (make not-visible — the
  latter two correctly *share* a verb, since they really are the same
  outcome, just not the wrong one). Backing module renamed
  `video_clip_announcement` → `video_clip_publication`, functions
  `announce_published/1`/`announce_retracted/1` →
  `publish_to_mesh/1`/`withdraw_from_mesh/1`; the payload's
  `announced_at` field (no longer accurate once the fact isn't called
  "announced") renamed `sent_at` — zero consumer impact, nothing on
  the macula-realm side reads that field yet.

  Each PM is a single-event `evoq_event_handler`, registered as its
  own worker in `guide_tube_lifecycle_sup`. `video_clip_publication` is
  the shared send-to-mesh module they all call into, mirroring
  `channel_announcement`'s own already-established shared-module
  pattern (called by both its write-reactive emitter and its
  heartbeat) — `channel_announcement` keeps its name; "announced" is
  still the right word there, a heartbeat is a genuine repeated
  announcement of current state, not a publish/withdraw pair.
  `channel_announced_v1_to_mesh` is left as a single module for now,
  unchanged — a reasonable follow-up to give it the same `on_*`
  treatment later, not done here.
- `Tube.SubscriberStarter` subscribes 4 topics now (was 3):
  `channel_announced_v1`, `video_clip_published_v1`,
  `video_clip_retracted_v1`, `video_clip_viewed_v1`.
- `ProjectTubeCatalog.upsert_video_clip/1` (the old action-switching
  entry point) split into `publish_video_clip/1` and
  `retract_video_clip/1`, each a direct, un-branching path — no more
  action-string matching anywhere in the realm's projection code.

Verified: `rebar3 compile` clean on hecate-tube, `mix compile` clean
on macula-realm, fresh local boot subscribes all 4 topics with no
crash. **Not yet re-verified against a live clip fact on the new
topics** — hecate-tube's beam02 deployment still runs the pre-split
image until this is pushed and watchtower rolls it; that re-verify
should happen right after the next deploy, the same way the mcid fixes
were verified against real traffic rather than assumed correct from a
clean compile.

### 16.3 Open: a scan step before a clip can be published (not yet designed to a build-ready shape)

Raised in review, not yet implemented: duration and a thumbnail are
essential, not nice-to-haves, for a real video catalog — a wall of
text-only titles with no length and no preview is a weak product. Get
there via a real technical-validation step, not silently bolting
`ffprobe` calls onto the existing upload handler:

- **Nothing in this codebase decodes video today.** The route is a
  synchronous `ffprobe`/`ffmpeg` shellout (`alpine:3.22` runtime,
  `apk add ffmpeg` is a one-line Containerfile change, no build step
  needed) — duration, and a thumbnail frame extracted only when the
  owner didn't supply their own (theirs wins).
- **This implies new domain events, not just new fields on the
  existing ones** — a scan is itself a business fact a clip goes
  through, not incidental metadata bolted onto `video_clip_uploaded_v1`.
- **Trigger point, resolved:** the scan can only start once the file
  is fully on hecate-tube's own disk (`local_ref` known) — that's the
  earliest point scanning is even physically possible, and it's also
  exactly the moment `video_clip_uploaded_v1` already carries. So the
  trigger is a PM reacting to that event
  (`on_video_clip_uploaded_scan_clip`, same shape as §16.2's
  announce-PMs), not something bolted inline into
  `tube_video_clip_upload_page:do_upload/3`. Async, not blocking the
  owner's POST: ffmpeg work on an arbitrary-length upload has no
  bounded latency, and CQRS's own "DB/external I/O never blocks the
  event flow" principle applies just as much to a shellout as to a DB
  call. The PM dispatches a follow-up command with the result —
  `record_video_clip_scanned_v1` (duration_ms, derived thumbnail_mcid)
  or `record_video_clip_scan_failed_v1` (reason) — once ffmpeg
  returns.
  Still open before this is build-ready:
  - Does a failed/missing scan **gate** `publish_video_clip` (aggregate
    guard against a new status bit, e.g. `?VIDEO_CLIP_SCANNED`), or is
    scanning purely enriching and publish stays ungated for v1? ("publish
    can only happen once the file is on hecate-tube's disk" already
    implies *upload* gates publish; whether a completed *scan* also
    gates it is the open part.)
  - v1 scope: duration + thumbnail only, or does "scan" already imply
    a broader content-validation surface (format/codec allowlist,
    corrupt-file rejection) that should be named and slotted in now
    even if only duration/thumbnail ship first?
- **A default/placeholder thumbnail** is still needed for whatever
  fraction of clips a scan can't extract a frame from (corrupt, near-
  zero-length file) — belongs on the macula-realm side (a static
  asset + template fallback), since that's where a thumbnail actually
  renders to a viewer; nothing renders `thumbnail_mcid` anywhere yet
  on either side, so this has no user-visible effect until image
  rendering itself is wired up.

Superseded by §16.4 below — resolved, not deliberately deferred any
more: sync inline (not async/PM), gated, duration+thumbnail-only v1
scope. Keeping this section as written for the trail of *why* the
sync-vs-async call flipped.

---

## 16.4 Scan pipeline built + verified live (2026-08-23)

**Scope locked in:** duration + width/height/codec/container_format/
file_size_bytes/has_audio + thumbnail, via `ffprobe`/`ffmpeg`. Three
new domain events, not new fields on `video_clip_uploaded_v1`:
`video_clip_scanned_v1` (measurements), `video_clip_accepted_v1` /
`video_clip_rejected_v1` (verdict) -- kept separate per §16.3's own
reasoning (1:1 for v1, diverge once scan gains a real pass/fail
policy). `uploaded` fires either way; there is no event-less silent
failure path any more -- a rejected upload is a real, queryable fact.

**Placement, corrected in review:** first draft put the ffmpeg
shellout in the HTTP handler (`tube_video_clip_upload_page:do_upload/3`).
Caught in review: scanning is a business rule of the `upload_video_clip`
command itself -- part of its own Chain of Responsibility (upload ->
scan -> verdict) -- not a transport-layer concern. Moved into
`maybe_upload_video_clip:handle/1`, called from the aggregate's
`execute/2`. Checked before committing to this: `evoq_aggregate.erl:76`
dispatches via `gen_server:call(Pid, {execute, Command}, infinity)` --
no evoq-side timeout to trip, so a multi-second scan is safe there.
`video_clip_scan.erl`'s own `?PROBE_TIMEOUT_MS`/`?THUMBNAIL_TIMEOUT_MS`
(15s each, `port_close/1` on expiry) are the only bound -- a corrupt or
adversarial file can't wedge the clip's aggregate process forever.

**This also supersedes §16.3's "async, via a PM" trigger design** --
that reasoning (CQRS's "external I/O never blocks the event flow")
was overapplied: it protects the evoq pipeline, not a per-request HTTP
handler already blocking on the multipart stream anyway. ffprobe
(header read) and a single seeked frame grab are sub-second-to-low-
seconds operations, not the unbounded case that principle exists for.

**Layering fix this required:** `tube_content_put.erl` (the
`macula_feeder` wrapper needed to push a derived thumbnail through
Content) lived in `hecate_tube` (the web app) -- unreachable from
`guide_tube_lifecycle` (CMD), since the dependency only runs the other
way (`hecate_tube` depends on `guide_tube_lifecycle`, per both
`.app.src` files). Moved to `guide_tube_lifecycle/src/`, same module
name, so both existing call sites (`tube_channel_configure_page.erl`'s
logo upload, `tube_video_clip_upload_page.erl`'s owner-thumbnail
upload) kept working unchanged.

**Gating:** `publish_video_clip`'s aggregate guard
(`video_clip_aggregate.erl`) now also requires
`Status band ?VIDEO_CLIP_REJECTED =:= 0`. No separate ACCEPTED bit --
`UPLOADED band not REJECTED` already means exactly that, and the two
are mutually exclusive/exhaustive given the current event set
(`tube_video_clip_status.hrl`).

**Thumbnail failure is non-fatal, duration/metadata failure is
fatal.** A valid-but-too-short-to-seek clip (the 1-second test fixture
below hits exactly this) still gets accepted, with `thumbnail_mcid =
undefined` falling back to the realm's placeholder (§16.3, not yet
built). An unreadable/corrupt file fails the whole scan -> the whole
upload is rejected, no `scanned` event (no real measurements exist to
record).

**Owner-facing feedback:** dashboard clip cards show a `rejected`
status with the reason (`tube_dashboard_page.erl`'s new
`rejection_notice/2`) and no publish/retract/archive buttons, just
"Try uploading again" -- matches the pattern from the earlier owner-UI
question about card-level feedback, but needed nothing beyond what
already existed (no cancel button, no in-progress state -- see the
async-vs-inline resolution above for why). The upload form's own
redirect distinguishes a clean accept ("Clip uploaded, private until
you publish it.") from a rejection ("Video rejected: <reason>",
redirected back to the upload form, not the dashboard) by inspecting
the dispatch result's returned events for a `video_clip_rejected_v1`
(`tube_video_clip_upload_page.erl`'s `rejection_reason/1`) -- a
rejected upload is `{ok, Events}`, not `{error, _}`, since the command
was validly processed into a recorded verdict either way.

**Verified live, not just eunit.** `rebar3 as prod release` +
`_build/prod/rel/hecate_tube/bin/hecate_tube foreground`, real HTTP
traffic via `curl` against the actual owner routes:

- Configured a channel, then uploaded a real, tiny (2KB, 1s, 32x32,
  h264, no audio) generated test fixture
  (`apps/guide_tube_lifecycle/test/fixtures/tiny_clip.mp4`, built with
  `ffmpeg -f lavfi -i testsrc=...`) through the actual multipart
  endpoint. Accepted, as expected; confirmed the thumbnail-extraction
  non-fatal path fired too (1s seek on a 1s clip can't land a frame --
  `thumbnail_mcid` came back `undefined`, upload still succeeded).
- Published the accepted clip -- worked.
- Uploaded a genuinely corrupt file (plain text renamed `.mp4`) through
  the same endpoint. Rejected, redirected back to the upload form with
  ffprobe's real stderr in the flash message, dashboard shows
  `status-rejected` with the reason, **no publish button rendered at
  all** for that clip -- confirmed the UI-level guard and the
  aggregate-level guard agree, not just the aggregate alone.

Two pre-existing, unrelated boot-config gaps hit along the way (not
scan-pipeline bugs): `HECATE_REALM` needs a real 32-byte/64-hex value
or `hecate_om_identity:load_realm/0` case-clause-crashes on an empty
string default, and `HECATE_DATA_DIR` needs a writable path (defaults
to `/var/lib/hecate-tube`, doesn't exist in a dev sandbox) or
`hecate_om_store:ensure_store/5` fails `enoent`. Neither blocks a real
deployment (both envs are already set correctly in
`macula-demo/infrastructure`'s beam02 config), only local ad hoc
verification runs.

**Test coverage:** `channel_aggregate_tests.erl`'s
`video_clip_aggregate_lifecycle_test` was pinned to a fake
`local_ref` (`/data/clip1.mp4`) that never needed to exist before the
scan step existed -- updated to point at the real fixture and assert
on all three success-path events. Added
`video_clip_upload_rejects_unreadable_file_test` for the rejection
path (asserts the exact rejection reason, the resulting bit-flag
value, and that `publish_video_clip` is correctly refused afterward).
34/34 eunit passing, `rebar3 compile` clean.

**Not done, deliberately:** the mesh fact (`video_clip_published_v1`)
and macula-realm's `ProjectTubeCatalog`/`VideoClip` schema don't carry
duration/resolution/etc. yet -- extending them is a small, low-cost
follow-up (the projection already has the data in `project_tube_store`'s
row) but wasn't asked for in this pass and is its own explicit
decision, matching how every other realm-facing change this session
got its own confirmation step.

**Committed, pushed, deployed** (2026-08-23, same day) -- corrected
from the "not yet committed" note this section originally closed
with. Also shipped in the same wave, live-verified against beam02's
real channel (all four caught things this session's local-only
testing couldn't have): the upload form reordered (video file first,
then metadata -- title/description/tags were awkwardly ahead of the
thing they describe), the channel logo actually renders now
(`tube_content_get.erl` + `GET /owner/content/:mcid_hex`, both new),
and a real bug in that: `macula_download:start_link_direct` can only
resolve *chunked* content via its DHT `content_announcement` -- a
small logo is nowhere near that threshold and 404'd even seconds
after the station's own upload, fixed by switching to pooled
`macula_download:start_link/4,5` to match how `tube_content_put`
already puts small content via the pooled `macula_feeder`, not
`_direct`.

### 16.5 Open: the owner upload flow's UX is dated, revisit later

Raised after the scan pipeline shipped, not actioned: the upload form
is a plain `<input type="file">` + a separate `Upload` submit button,
full-page POST+redirect, zero client-side feedback between "file
selected" and "redirect back with a flash message" -- no drag-and-
drop, no inline progress, no visible "scanning..." state, nothing
happens at all until the owner notices the Upload button and clicks
it. This was a deliberate call at design time (no JS/htmx, see PART1
§8.1's resolution and the async-vs-inline reasoning in §16.4), correct
for what it was solving then, but the owner-facing result reads as
dated next to how uploads work on any real platform today.

Not scoped or designed here -- explicitly deferred, "for now" (the
owner's own words) doing it manually through the current form. Revisit
as its own pass: whether this actually needs JS/htmx after all (the
no-JS decision predates the scan pipeline, which is exactly the kind
of multi-second, no-feedback gap that makes the tradeoff worth
re-litigating), or whether a plain-HTML incremental improvement
(e.g. an intermediate "uploading, please wait" interstitial page) gets
most of the value without reopening that decision.
