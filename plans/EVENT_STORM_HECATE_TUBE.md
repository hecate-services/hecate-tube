# Event Storm: hecate-tube + macula-realm `tube`

**This exists so a channel owner's edge node and the macula-realm catalog have
one concrete, corpus-consistent event model to build the "crafting" phase
against, instead of Phase 0's thin guesswork.**

**Status:** Storm complete, reviewed with the user 2026-08-22 (three
corrections below), crafting session now underway. **MVP-scoped:** the
owner explicitly cut live broadcast from this pass — PART1 §8.4, §9.3, §9.4,
§9.6 (everything downstream of `go_live`/`end_live`/the live→clip Policy) are
parked, not designed against, until a later session.

**Companion docs:** `plans/PLAN_HECATE_TUBE_ROOT.md` (handover, hard-won
technical facts, Phase 0 inventory) and `specification/SPECIFICATION.md` (the
product spec this storm is grounded in). Read both before this if you
haven't. This doc does not repeat their content except where a specific fact
is load-bearing for a specific decision below.

**Split into two content files 2026-08-23** (this file crossed the
workspace's own 75KB/1500-line threshold for plan documents — see the root
CLAUDE.md "Documentation Structure Guidelines"). This file is now the
root/TOC; the storm and its content live in:

- **[`EVENT_STORM_HECATE_TUBE_PART1.md`](EVENT_STORM_HECATE_TUBE_PART1.md)**
  — the original event-storm design: sections 0 through 9 (how the storm was
  run, the macula API, the Channel/VideoClip dossiers, integration facts,
  primitive wiring, the macula-realm side, the six SPECIFICATION §6
  resolutions, and what the storm surfaced beyond them).
- **[`EVENT_STORM_HECATE_TUBE_PART2.md`](EVENT_STORM_HECATE_TUBE_PART2.md)**
  — the crafting-session implementation log: sections 11 through 16.4
  (hecate-om/macula-SDK findings, the Phase 0 punch list, crafting session
  status, the owner-facing web UI, the macula-realm build, the mesh-fact
  contract revision, and the scan pipeline).

Section numbering has a pre-existing gap (§10 was never used) and is kept
exactly as originally written across both files — cross-references like
"§16.2" or "PART1 §5.3" refer to the section number, not file position, and
mostly still work whichever file you're in; a few are written as explicit
`PART1 §N`/`PART2 §N` where the split makes that ambiguous. Code comments
across both repos citing `plans/EVENT_STORM_HECATE_TUBE.md sec N` remain
valid as written — this root file's continued existence at the same path is
exactly why the split didn't rename it.

**Update, same day (pre-split):** §0 (PART1) described a first pass grounded
in macula's facade docstrings and one guide (Streaming). A follow-up
deep-read of every macula SDK guide plus hecate-om's actual source (§0.5,
PART1) found that pass was using one layer too low: every provider/consumer
desk in §5 should call the SDK's supervised OTP-behaviour wrapper modules
(`macula_publisher`/`macula_subscriber`, `macula_response`/`macula_request`,
`macula_feeder`/`macula_download`, `macula_streamer`/`macula_stream_sink`),
not the raw `macula:publish`/`subscribe`/`call`/`advertise`/`put_content`/
`get_content` facade calls §4-§5 originally named. That correction is
applied throughout PART1 §4-§5 and §7, and folded into PART2 §11-§12 (an
audit of what hecate-om already wraps vs. what hecate-tube newly exercises).

A same-session detour also considered replacing the PubSub-based
catalog-discovery design in PART1 §4 with DHT Records (`macula:put_record` +
a custom domain type tag) — **rejected.** DHT records are the mesh's own
infrastructure-self-description primitive (how to reach a station, what it
serves); a channel's name/description/tags is domain data, and this
workspace's own Domain-Events-vs-Integration-Facts principle already
designates PubSub topics as the transport for exactly that, precedented by
mpong-bot's `game_advertised`/`state_broadcast`. PART1 §4 is PubSub +
heartbeat, as first drafted — read it as final, not as superseded.

**Update, 2026-08-22 (crafting-session review — three corrections to the
storm as originally written):**

1. **The §12.2 streamer gap is fixed at the source, not worked around.**
   Reading `macula_streamer.erl`'s `open/7` directly (not just its
   moduledoc) found the real bug: on `handle_open/2` returning `{stop,
   Reason, _}`, `StreamPid` was never linked and never aborted — `init/1`
   fails, `terminate/2` never runs (OTP semantics), and the peer that
   opened the stream got silence instead of a signal, until its own 30s
   `recv` timeout. Fixed in `macula-io/macula` — the existing `{stop,
   Reason, NewState}` return now calls `macula_stream:abort/3` on the
   stream before failing init. No callback contract change, no version
   bump beyond patch. `stream_video_clip_by_id`'s `handle_open/2` (PART1
   §5.2) just returns `{stop, not_found, State}` for an unpublished clip —
   no spawned-helper workaround needed, PART1 §5.2/§12.2's workaround text
   is superseded by this.
2. **View count gets a mesh fact after all — on its own topic, not the
   catalog rendezvous topic.** PART1 §4.4's "don't push per-view" reasoning
   was an argument against the ONE topic every channel's discoverability
   heartbeat shares (PART1 §4.2's fixed rendezvous topic), not against ever
   publishing view activity. New fact `tube.video_clip_viewed_v1` (topic
   `io.macula/tube-commons/tube/video_clip_viewed_v1`, payload `clip_id,
   channel_id, viewed_at` — no `viewer_ref`, same privacy discipline as
   every other fact) lets `project_tube_catalog` keep a `view_count`
   column warm incrementally, which is what actually lets a channel grid
   show view counts for many clips without N RPC round-trips per render.
   `advertise_video_clip_lookup` (PART1 §5.3) is unchanged and still the
   authoritative, guaranteed-fresh source for the single-clip detail page
   — push for cheap catalog freshness, pull for authoritative freshness,
   not an either/or the way PART1 §8.2 originally framed it.
3. **§7.1/§9.2's "no new app" conclusion is wrong for `tube` (right for
   `tube_web`).** `macula_realm` is a genuinely different bounded context
   (accounts, API keys, cert issuance — see its own CLAUDE.md) from Tube's
   catalog-subscriber/remote-lookup glue; deferring to Mpong's placement
   inside it repeats exactly the kind of DIY-shortcut-as-precedent this
   project was explicitly told not to blindly copy. Corrected: **`tube` is
   its own new sibling OTP app** (`apps/tube/`, alongside
   `project_tube_catalog`/`query_tube_catalog`), holding `Tube.Subscriber`
   and `Tube.RemoteLookup`. `tube_web` stays as originally written — no
   new app, LiveViews live inside the existing `macula_realm_web` app —
   but under a `Tube.` module namespace (`MaculaRealmWeb.Tube.TubeLive`,
   `.VideoLive`, `.TubeStreamController`), not flat top-level modules.
   PART1 §7.3's module list and the blockquote in §7.1 are stale against
   this; read this note as authoritative over both.

---

## Status at a glance

| Area | State | Where |
|---|---|---|
| Storm/design | Complete, reviewed | PART1 |
| Channel + VideoClip CMD desks | Built, eunit-green | PART1 §1-2, PART2 §14 |
| Live broadcast (`go_live`/`end_live`) | Parked, MVP cut | PART1 §9.3 |
| Owner-facing web UI | Built, verified live | PART2 §15 |
| macula-realm `tube`/catalog/LiveViews | Built, verified live | PART2 §16 |
| Mesh-fact contract (`video_clip_*`) | Revised: two topics, no `action` field | PART2 §16.2 |
| Scan pipeline (duration/thumbnail/accept/reject) | Built, verified live | PART2 §16.4 |
| Realm-side duration/resolution display, default thumbnail | Not started | PART2 §16.3, §16.4 |
| Commit/push/deploy of the current working tree | **Not done** | — |

## Table of contents

**PART1** — the storm:
§0 How this storm was run · §0.5 The high-level macula API · §1 Channel
dossier · §2 VideoClip dossier · §3 Live → Clip Policy · §4 Integration
facts · §5 Primitive wiring, desk by desk · §6 Cross-division Process
Managers · §7 macula-realm side shape · §8 The six SPECIFICATION §6
resolutions · §9 What the storm surfaced beyond those six questions.

**PART2** — the build:
§11 hecate-om today · §12 hecate-om/macula-SDK findings log · §13 Punch list
against Phase 0 · §14 Crafting session status · §15 Owner-facing web UI +
hex/deploy chain · §16 macula-realm side + mesh-fact contract revision
(§16.1 two live bugs, §16.2 the published/retracted split, §16.3 the scan
step, originally left open, §16.4 the scan pipeline as built).
