echo "Install the speaker tuning for XPS 2026 14/16"

# Speaker tunings are PipeWire filter-chain drop-ins gated on a hardware
# predicate, so this is a no-op on machines without one. The limiter is an LV2
# plugin and the graph will not instantiate without it.

if omarchy-audio-tuning match >/dev/null 2>&1; then
  omarchy-pkg-add lsp-plugins-lv2
  # A tuning that can't apply yet (EasyEffects running, no audio server during
  # the update) must not stop the remaining migrations.
  omarchy-audio-tuning on ||
    echo "Speaker tuning not applied yet. After logging in, run: omarchy audio tuning on"
fi
