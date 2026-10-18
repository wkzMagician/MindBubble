# Note covers

Cover controls live in the note editor. A note can use a generated text cover or
one of its Markdown images. Original titles follow title edits; refined and
manually edited headlines stay selected until changed explicitly.

`lib/features/note_cover` contains the cover metadata, renderer, image discovery,
configured-model headline service, artwork widget, and editor controls. The app
continues to use the Dartloom model contracts and the user's saved model access
configuration.

The renderer uses a persisted random seed, high-contrast color pairs, and
procedural background shapes. It measures graphemes and protected phrases,
prefers fewer lines at a readable font size, then balances the lines. Text stays
in a 760 × 580 safe area inside a 1024 × 1024 PNG, with compact line spacing.
Model phrases and common Chinese grammatical units remain intact. Renderer
version 4 automatically refreshes older cached posters without changing their
chosen text or random seed.

Generated PNGs are normal content-addressed note attachments. Cover settings and
the artwork signature are optional fields in the existing document metadata.
Older documents remain readable. Their visible covers are prepared lazily and
merged only if the note and selected cover are still unchanged; exposure,
feedback, and analysis changes are retained. This cache write schedules sync
without drawing another homepage batch.

Changing the picture seed keeps the headline. Changing the headline keeps the
seed. Canceling the editor does not save either change. Imported source updates
keep a user's selected cover, while duplicated notes receive their own cover.

Ocean content is clipped inside each bubble. The physics radius includes the
rim, deformation, and hover enlargement. Hover pauses movement. Dense windows
use pages, and only newly visible notes are recorded as exposed in each refresh
batch. Image containment reserves a safe rectangle and a separate title area;
fill mode supports dragging and horizontal/vertical focal controls.

Run `flutter test` for cover metadata, PNG bounds, source-evidence validation,
save/cancel behavior, image selection, stale requests, and visible-page exposure.
Set `MINDBUBBLE_VISUAL_OUTPUT` to an existing output directory to have the cover
editor tests also capture Flutter renderings. On Windows the preview tests load
Microsoft YaHei when available; `MINDBUBBLE_TEST_MATERIAL_FONT` can point to the
Flutter SDK's MaterialIcons font for those captures.
