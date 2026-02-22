#!/usr/bin/env bash
set -euo pipefail

target="${1:-hvt}"

mirage configure -t "$target" --no-extra-repo

# Ensure dune-universe overlays exist in the current switch for opam-monorepo lock.
opam repository add dune-universe git+https://github.com/dune-universe/opam-overlays.git \
  || opam repository set-url dune-universe git+https://github.com/dune-universe/opam-overlays.git
opam repository add dune-universe-mirage git+https://github.com/dune-universe/mirage-opam-overlays.git \
  || opam repository set-url dune-universe-mirage git+https://github.com/dune-universe/mirage-opam-overlays.git

python3 - <<'PY'
import re
from pathlib import Path

makefile = Path('Makefile')
if not makefile.exists():
    raise SystemExit('Makefile not found; run from mirage directory')
s = makefile.read_text()
s = s.replace(
    '$(OPAM) repo remove opam-overlays https://github.com/dune-universe/opam-overlays.git',
    '-$(OPAM) repo remove opam-overlays',
)
s = s.replace(
    '$(OPAM) repo remove mirage-overlays https://github.com/dune-universe/mirage-opam-overlays.git',
    '-$(OPAM) repo remove mirage-overlays',
)

# --- nano_os local-lib fix ---
# opam-monorepo cannot pull the parent project into its own mirage/
# subdirectory ("they overlap").  Inject patch-lockfile + sync-local-lib
# targets so the depends target handles this automatically.
OLD_DEPENDS = """\
depends depend::
\t@$(MAKE) --no-print-directory lock
\t@$(MAKE) --no-print-directory install-switch
\t@$(MAKE) --no-print-directory pull"""

NEW_DEPENDS = """\
depends depend::
\t@$(MAKE) --no-print-directory lock
\t@$(MAKE) --no-print-directory patch-lockfile
\t@$(MAKE) --no-print-directory install-switch
\t@$(MAKE) --no-print-directory pull
\t@$(MAKE) --no-print-directory sync-local-lib

NANO_OS_ROOT := $(abspath ..)
LOCKFILE := $(MIRAGE_DIR)/$(UNIKERNEL_NAME).opam.locked

patch-lockfile: $(LOCKFILE)
\t@echo " ↳ patch lockfile: exclude local nano_os from duniverse pull"
\t@python3 -c "\\
import re, pathlib; \\
p = pathlib.Path('$(LOCKFILE)'); t = p.read_text(); \\
t = re.sub(r'\\n\\s*\\[\\"file:///[^\\"]*nano_os[^\\"]*\\"\\s+\\"reponame\\"[^\\]]*\\]', '', t); \\
t = re.sub(r'\\s*\\[\\"nano_os\\.dev\\"\\s+\\"file:///[^\\"]*\\"\\]', '', t); \\
t = t.replace( \\
  'x-opam-monorepo-opam-provided: [', \\
  'x-opam-monorepo-opam-provided: [\\n  \\"nano_os\\"'); \\
p.write_text(t)"

sync-local-lib:
\t@echo " ↳ sync local nano_os library into duniverse"
\t@mkdir -p duniverse/nano_os
\t@rsync -a --delete \\
\t\t--exclude='mirage/' \\
\t\t--exclude='_build/' \\
\t\t--exclude='.git/' \\
\t\t--exclude='nano_disk.img' \\
\t\t$(NANO_OS_ROOT)/ duniverse/nano_os/

.PHONY: patch-lockfile sync-local-lib"""

if 'patch-lockfile' not in s:
    s = s.replace(OLD_DEPENDS, NEW_DEPENDS)

makefile.write_text(s)

dune_build = Path('dune.build')
if dune_build.exists():
    d = dune_build.read_text()
    if '(rule\n (targets manifest.c)' in d and '(enabled_if (= %{context_name} "solo5"))\n (targets manifest.c)' not in d:
        d = d.replace(
            '(rule\n (targets manifest.c)',
            '(rule\n (enabled_if (= %{context_name} "solo5"))\n (targets manifest.c)',
        )
        dune_build.write_text(d)

print('Patched Makefile + dune.build compatibility fixes')
PY

echo "Configured target: $target"
