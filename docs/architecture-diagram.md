# Architecture Diagram

```text
                     +----------------------+
                     |      launchd         |
                     | process supervision  |
                     +----------+-----------+
                                |
                                v
                     +----------------------+
                     |  OpenClaw Gateway    |
                     +----------+-----------+
                                |
                                v
                     +----------------------+
                     |  health-check.sh     |
                     | openclaw status loop |
                     +----------+-----------+
                                |
                    repeated failures reached
                                |
                                v
                   +--------------------------+
                   |    auto-heal-ai.sh       |
                   +------------+-------------+
                                |
                +---------------+----------------+
                |                                |
                v                                v
   +---------------------------+    +-----------------------------+
   | safe-backup restore path  |    | openclaw doctor --fix path |
   +---------------------------+    +-------------+---------------+
                                                  |
                                     recovered? --+-- yes --> done
                                                  |
                                                  no
                                                  v
                                 +--------------------------------+
                                 | AI fallback repair generation  |
                                 | safety check + apply + verify  |
                                 +--------------------------------+
```

This diagram is intended as a lightweight README-friendly text diagram.
A graphical version can be added later if needed.
