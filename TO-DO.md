# TO-DO

## Open

- [ ] **Rebuild `debs/direwolf_current_arm64.deb` on an arm64 host.**
  The amd64 package was rebuilt on Ubuntu 24.04 on 2026-09-30 (PR #3).
  The arm64 one is probably still linked against `libgps.so.28` and has
  no `Depends`, so on current releases it would install cleanly and then
  fail when direwolf starts. Rebuild it on an arm64 host such as a Pi:

  ```bash
  ./SIGedge package direwolf
  dpkg-deb -f debs/direwolf_current_arm64.deb Depends  # should list libgps30t64
  ldd "$(command -v direwolf)" | grep 'not found'      # should print nothing
  ```

  Then commit the new `debs/direwolf_current_arm64.deb`.
