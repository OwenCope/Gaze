# Admin navigation

The shared admin navigation is now a fixed 112px header with a compact Gaze website link, theme and account controls, and a separate row for Dashboard, New release, Tester notes, and People. The navigation uses native links with 44px minimum targets, visible keyboard focus, and horizontal overflow on narrow screens.

Active state follows the exact current pathname, so the Dashboard tab is selected only at `/admin` and does not appear selected while editing a release. The former marketing dock, section scrolling, icons, and scroll-driven motion were removed.

No build or browser verification was run in this task. Combined verification belongs to the root task.
