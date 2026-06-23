# racket-mcp

A Racket implementation of the Model Context Protocol (MCP) SDK, mirroring the architecture of the [MCP TypeScript SDK](typescript-sdk/).

See `docs/aide/vision.md` and `docs/aide/roadmap.md` for project goals and staged delivery plan, and `docs/aide/progress.md` for current status.

## Prerequisites

- **Racket** (v8.18 or later recommended)

  On Ubuntu/Debian:

  ```sh
  sudo apt update
  sudo apt install racket
  ```

  This installs both `racket` and `raco` (Racket's build/test/package tool). Verify with:

  ```sh
  racket --version
  raco --version
  ```

## Running tests

```sh
raco test mcp/core/types/ mcp/core/errors.rkt
```
