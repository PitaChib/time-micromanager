# Deadline update verification

57 checks passed: 38 existing core, 8 existing store workflows, 8 deadline/CSV core, 3 deadline persistence workflows. All mutation tests used temporary notebooks.

Optimized release, Apple Silicon host, one run:

| Entries | CSV size (MB) | Export (s) | Import (s) | Task statistics (s) |
| ---: | ---: | ---: | ---: | ---: |
| 1,000 | 0.23 | 0.007 | 0.007 | 0.005 |
| 20,000 | 4.56 | 0.141 | 0.126 | 0.043 |
| 100,000 | 22.85 | 0.655 | 0.608 | 0.211 |

Separate UI preview: 20,000 entries and 100 deadline tasks. Peak resident memory from in-process `getrusage` was 148.67 MiB at 5, 30, 60 and 120 seconds. Cumulative CPU at 120 seconds was 4 user seconds and 1 system second. These are short observations, not a leak soak or a controlled comparison with the old build. The benchmark covers parsing and statistics; it does not guarantee instant whole-app rendering at 100,000 entries. CSV import/export still execute synchronously and can briefly block the UI with very large files.

Native checks: start task; save time and description; complete; show completed summary. Installed release: launch, preserved prior totals, CSV export written and parsed through restore selection, cancellation preserves current data. Unit tests verify actual restore and backup writes in isolated stores. Installed and ZIP executables matched the signed release.
