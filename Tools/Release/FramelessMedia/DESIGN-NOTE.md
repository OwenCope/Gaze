# Product imagery: one visible boundary

The owner explicitly rejected screenshots nested inside additional web cards,
frames and letterbox mattes. Product art already carries its own background and
UI geometry. Its surrounding web elements should arrange it, not draw another box.

- Layout containers around product images stay transparent: no fill, padded well,
  border or shadow. Avoid nested rounded containers.
- Use the image's natural proportions. A single corner clip on the image itself
  is acceptable; do not decorate both the image and its parent.
- Controls and captions sit beside or below the image instead of creating more
  chrome over it. The native viewer retains accessible close/focus behavior.
- Keep lossless detail sources and native-density size limits. Never stretch a
  small capture to fill a card, crop complete sentences, or fake missing glass.
- Preserve the measured 0.6-speed hero preview and 400ms pointer gallery fade.
  Keyboard and reduced-motion changes remain immediate.
