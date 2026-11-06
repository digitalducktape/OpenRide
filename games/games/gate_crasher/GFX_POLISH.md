# Gate Crasher: graphics punch list

Self-review of the first captures against The Pull and Dodge Ball, 2026-11-06.

**What works:** the bright sand and grass against the sky, the striped grandstand, painted fences
that read from far off, the sense of speed from the ring fence.

1. **Done.** The neck filled the middle of the frame as a smooth column and hid the fence during a
   jump. Rebuilt wide and low, in the bottom third; a bounds test keeps it there.
2. **Done.** The mane was invisible, then a rope, then a centred strip that failed the silhouette
   check. Now ragged locks to the right of the crest.
3. **Done.** The chevrons lit under the horse, where nobody saw them. The whole approach now turns gold
   at the first beat.
4. **Done.** Landing dust drew as hard squares: a soft disc now. Confetti burst in the rider's face:
   smaller, and 14 m ahead.
5. **Skipped.** Crowd figures are flat at close range on the first straight. They pass at 8 m/s, and
   a mesh crowd would cost draw calls for no gain in play.
6. **Skipped.** A shadow under the fences: the AO in the vertex colours carries it, and a blob
   shadow per fence means more transparent fill on the tablet.
