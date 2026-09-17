# Missing-page view

Added a restrained Gaze-branded `not-found.tsx` to the website and its SecondaryPages source copy. The Server Component uses the existing icon, theme tokens, action styling, and `site-link`, with clear routes back to Gaze and to releases.

The view leaves Next.js in control of unmatched-route status and automatic `noindex` handling. It does not inspect the request, fetch release data, or make claims about release visibility or authorization.
