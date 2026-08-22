# hecate-tube — Product Specification

**This exists so a channel owner can run their own YouTube-like TV channel on
their own edge hardware, broadcasting live and on-demand video to mesh
consumers over Macula, without surrendering their content to anyone else's
platform.**

**Status:** Draft — captures the spec as given 2026-08-21/22, plus proposals
from the first design-conversation pass. Proposed material is explicitly
marked as such throughout; nothing marked "proposed" is confirmed.

---

## 1. What hecate-tube is

`hecate-tube` is a **daemon (service)** intended to run on an **edge node**
(the owner's own hardware — a MaculaOS device, a home server, anything the
owner controls) and communicate with consumers over the **Macula relay
mesh**. It is heavily inspired by YouTube, reimagined as mesh-native and
self-hosted rather than platform-hosted.

Its purpose: let the owner run a **mesh-native "TV Channel"** carrying:

- A number of **video clips** (recorded content).
- **Live video streams**, which **turn into video clips once the broadcast
  completes** — the live session is recorded, and the recording becomes a
  clip in the channel's library afterward.

## 2. The privacy boundary — upload is not publish

Video clips **remain on the edge node** and are **not disclosed to the mesh**
unless the owner **explicitly publishes** them. Uploading a clip is a private
act; publishing is the act that makes it discoverable and streamable by mesh
consumers. A clip can presumably move back to private (**retracted**) after
being published, and can eventually be removed permanently — see the open
naming question in §6.

## 3. Streamed, not downloaded

When a consumer chooses to view a clip — live or already-recorded — the clip
is **STREAMED** to them. It is never bulk-transferred/downloaded as a whole
file. This holds for VOD replay of a stored clip exactly as it holds for a
live broadcast: hecate-tube streams bytes off local disk (or off the live
feed) on demand, chunk by chunk, to each viewer.

This is the single detail that most reshapes the technical design (see
`plans/PLAN_HECATE_TUBE_ROOT.md`'s primitive-pair mapping) — it means the
mesh Content primitive (bulk blob put/get) is **not** the video-bytes path
for viewing at all.

## 4. The owner's web UI

The daemon itself **provides a web UI** to the owner (served by hecate-tube,
on the edge node) covering:

- **Configure** the channel (name, description, tags, logo, ...).
- **Upload** a video clip (private, local-only at this point).
- **Publish** a video clip (make it mesh-discoverable and streamable).
- **Retract** a video clip (make it private again).
- **Delete** a video clip (permanent — naming open, see §6).
- **Guide the channel's lifecycle** more generally (go live, end a live
  session, etc.).

*Proposed, not confirmed:* Erlang has no LiveView equivalent, so this is
realistically a plain cowboy-rendered HTML UI (possibly with htmx-style
progressive enhancement for interactivity), not a reactive/live-updating UI
the way the consumer-facing macula-realm side can be. Open question — see §6.

## 5. Metadata

### Channel

- name
- description
- owner
- video clips (the channel's clip library — metadata, not full clip content)
- tags
- logo
- *(open-ended — "...", more fields expected as the design matures)*

### Video clip

- name
- description
- thumbnail
- number of views
- tags
- *(open-ended — "...")*

*Proposed, not confirmed:* logo and thumbnail are small, discrete,
fetch-once, cacheable images — a genuinely honest fit for the mesh
**Content** primitive (macula_feeder/macula_download), distinct from the
video bytes themselves (which are always Streaming, per §3). View count is
presumably incremented by consumer viewing activity, not by the owner — see
open question in `plans/PLAN_HECATE_TUBE_ROOT.md`.

## 6. Open questions (not yet resolved — resolve AFTER the full event-storming pass, per explicit instruction)

1. **Owner UI tech** — plain cowboy HTML (+ maybe htmx), or something else?
2. **View counting** — does hecate-tube count views locally (it mediates the
   stream connection) and publish a count/fact, or does the realm-side
   aggregator (§7) count them since it mediates discovery?
3. **Peer-to-peer "follow another channel"** — does this still matter now
   that there's a centralized realm-side catalog, or does discovery go
   exclusively through macula-realm?
4. **Live → clip**: does the recording land already-published (it was public
   while live) or private-by-default, requiring the owner to explicitly
   publish the recording afterward?
5. **Channel↔clip relationship**: clips as their own aggregates with the
   association built on the read (QRY) side, or embedded in the channel
   aggregate's own write-side state?
6. **Naming**: `delete_video_clip` trips Hecate's CRUD-taboo naming
   convention (`created`/`updated`/`deleted` are forbidden event verbs).
   Candidates: `discard_video_clip`, `retire_video_clip`,
   `remove_video_clip`. Whichever reads right for the product.

## 7. The consumer-facing side: a separate service on macula-realm

Viewing/browsing is **not** done through hecate-tube's own UI. A separate
**"tube" umbrella service**, hosted on **`macula-io/macula-realm`**
(confirmed existing — see the handover doc), provides:

- A **LiveView** (`TubeLive`) on macula-realm for browsing channels/clips.
- Possibly a separate `VideoView`/`VideoLive` for single-clip playback
  (open — the split hasn't been decided, just floated).
- Backing logic that **subscribes to integration facts** hecate-tube
  services publish onto the mesh (channel configured, clip published,
  went live, ...) and **maintains an aggregated, cross-channel view** of
  everything available — a catalog spanning every hecate-tube instance on
  the mesh, not just one channel.

This is a **second deployable**, in a **different stack** (Elixir/Phoenix,
not Erlang) — `macula-realm/system/` is already a Phoenix umbrella using the
same CMD/PRJ/QRY convention hecate-tube uses (`guide_realm_lifecycle`,
`project_realm`, `query_realm`, `macula_realm`/`macula_realm_web`), so the
natural shape is new sibling apps there (`tube`/`tube_web` + whatever
PRJ/QRY apps the aggregator needs), not a new repo.

See `plans/PLAN_HECATE_TUBE_ROOT.md` for the technical handover, what's
already built, and where the next session should resume.
