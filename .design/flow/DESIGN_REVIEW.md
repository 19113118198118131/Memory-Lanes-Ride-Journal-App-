# Flow design review

## Intent

Flow is a quiet post-ride breathing instrument, not a game dashboard. The rebuild uses a restrained retro hi-fi language: a calibrated dial, a single luminous signal, technical edge markings, and an asymmetric gather and release rhythm.

## Review summary

- The breathing cue is now the dominant visual at every viewport.
- Check-in is one clear decision with no competing primary action.
- Ritual controls are progressively disclosed and the close control remains available.
- The canvas fills the viewport at phone, tablet, and desktop sizes.
- The old road, mountain, score, and arcade visual language has been removed from the active renderer.
- Motion settles over the session and the same clock drives the dial, mark, trace, and ambient field.
- Reduced motion retains the timed phase text and simple pacer.

## Responsive captures

- `screenshots/flow-checkin-375x812.png`
- `screenshots/flow-ritual-375x812.png`
- `screenshots/flow-checkin-768x1024.png`
- `screenshots/flow-checkin-1280x800.png`

## Verification

- Browser console: no errors or warnings.
- Keyboard-accessible native buttons retained.
- Mobile safe-area padding retained.
- No `!important` declarations added.
- Flow logic test suite: 15 passed.
