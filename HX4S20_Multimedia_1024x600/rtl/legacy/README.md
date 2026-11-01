# Historical RTL references

These six modules are excluded from the active sources.f. Existing standalone
tests still need them, so rtl/<name>.v remains a two-line compatibility include.
The implementations in this directory preserve the original bytes; Icarus
preprocessor token streams were compared before/after the relocation.

Run legacy scripts from the project root, as their existing runners do. This
organization does not reduce FPGA resource use: these modules were already
outside the active design. Do not re-add them to sources.f as an optimization.
