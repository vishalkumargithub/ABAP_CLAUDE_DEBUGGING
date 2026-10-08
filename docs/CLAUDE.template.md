# ABAP package export (ZGCTS_EXPORT)

<!-- Copy this file to the root of your export repository and name it CLAUDE.md.
     Claude Code reads CLAUDE.md at the start of every session. -->

This repository is a read-only export of an ABAP package, produced by the report ZGCTS_EXPORT.
It contains source code and repository metadata only, no business data.

## Layout

`objects/<PKGPATH>/<TYPE>/<NAME>/`

- `PKGPATH` is empty for the root package. Subpackage folders use the full package name in lower case, with `/` replaced by `#`.
- `METH <name>.abap` contains one method. `CLSD`, `CPUB`, `CPRO` and `CPRI` are the class definition and sections, and `CINC ...CCIMP/CCDEF/CCAU` are the local classes and tests.
- `FUNC <name>.abap` contains a function module body, and `FUNC <name>.$.abap` its signature.
- `REPS <name>.abap` contains a program or include, `REPT` its text pool, and `DYNP <nnnn>` a screen.
- `<TYPE> <NAME>.asx.json` contains the dictionary and repository table rows:
  - `DD02L` / `DD03L` hold table fields and keys, and `DD05S` / `DD08L` the foreign keys.
  - `DD07L` / `DD07T` hold the domain fixed values, which are the meaning of status codes.
  - `T100` holds message texts (in `MSAG/<class>/`).
  - `TMDIR` maps a class's method includes (`...CMnnn`, as named in ST22 short dumps) to methods.
  - `TSTC` maps a transaction to its program.
- In file names, `~` is written as `%7E` and `/` as `%2F`.
- `.zgcts/export.json` and `git log` show which transport request changed what. There is one commit per transport.

## Knowledge graph

- The graph is in `kg/graph.json`, and a summary of entry points and message origins is in `kg/README.md`.
- Use the graph first, then confirm in the source file.
- After each new export, update the graph for the changed files only.

## Rules for analysis

- Cite a file and line for every claim.
- You cannot see runtime values, so do not guess them. List the exact checks that would confirm or rule out each branch: the SE16 table with its key fields and the expected value, the SM37 job log line, or the ST22 dump detail.
- When a message is involved, list **every** statement that raises it before you choose one.
- A root cause is only accepted if it explains every observation in the ticket.
- Keep fixes minimal: name the method file(s) to change and every caller that is affected.
- Write results in this structure: Symptom, Origin, Failure chain, Root cause, Proposed fix, Verification on the system, Why this explains all observed behavior, Objects involved.
