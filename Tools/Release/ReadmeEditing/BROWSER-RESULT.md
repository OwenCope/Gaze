# Notes editor browser result

Tested the actual integrated component in the synthetic fixture on localhost.
The router and transport are stubs; no real notes, account or endpoint was used.

- Submit seed-A, type newer draft B while pending, resolve A: B remains editable
  and Saved is false.
- Submit B, send Cmd+S while pending: one pending request, with no duplicate send.
  Resolve B: Saved is true for B.
- Type C, submit, return HTTP200 with unparseable HTML: C remains unsaved and
  an alert says the save could not be confirmed.
- The label identifies the textarea as Tester notes, busy state is exposed,
  and success/error use status/alert announcements.

Root also made shortcuts exact (no Shift/Alt variants) and added server-side
body validation: malformed/missing notes return HTTP400 without writes; explicit
empty-string notes remain an intentional clear. Eleven route cases pass with
real NextResponse and synthetic authentication/storage.
