# Release review

2026-10-29 · Godot 4.7.1

No blocking findings remain within the documented generator and example scope.

## Changes reviewed

- Removed repetitive and obsolete comments. All 21 changed core/data scripts
  retain the same executable token stream as the extracted version.
- JSON export now flushes and returns the write result instead of reporting
  unconditional success.
- Box walls and furniture use `BoxShape3D` instead of triangle-mesh collisions.
  Floor meshes retain their one-sided triangle collisions.
- The extraction tool writes to a fresh snapshot directory. Upstream snapshot
  hashes and current library hashes remain separate in `source_manifest.json`;
  all 24 current file hashes were checked.

## Verification

- `test_results.json`: **145 checks, zero failures**, covering 24 generated maps,
  deterministic layouts, export and collision-aware probe movement.
- Nine production-reference geometry fingerprints were independently regenerated
  and matched after cleanup.
- `ui-checks.json`: **14 checks passed**.
- `preview-25d-checks.json`: **15 checks passed**, including seed/floor preservation,
  matching 2D/3D geometry, replacement of old geometry and floor contact.
- Independent box-physics checks passed at three rotations: exact dimensions,
  inherited world transforms, face contact and clearance above each box.
- `physics_build_benchmark.json`: the median collision-geometry build changed
  from **9.658 ms to 6.584 ms**, with the same 261 bodies. This is a headless
  build-time measurement, not an FPS benchmark.

## Limits

Graph connectivity and conservative clearance samples do not prove that every
custom character can traverse every seed. Audit warnings remain visible. The
3D example approximates some nonrectangular furniture with boxes; use the full
collider data for exact custom physics. Generation is synchronous, and earlier
Godot versions and exported builds have not been exhaustively tested.
