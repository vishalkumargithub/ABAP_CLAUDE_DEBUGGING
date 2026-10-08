# ZGCTS_EXPORT

**Export an ABAP package as plain text, give it to Claude, and debug by asking questions instead of stepping through code.**

ZGCTS_EXPORT is one standalone ABAP report. It does not depend on anything else and **never writes to the SAP system**. It reads a package (or a single transport request) and downloads a ZIP file to your PC. The ZIP is laid out like a **gCTS repository** (JSON format, `formatVersion 6`), with folders for **package → object type → object**. Every method is its own file, and the dictionary data (fields, keys, domain values, message texts) is included as JSON. That makes the export easy for people to read, and very good input for an AI assistant such as **Claude**.

Written by **Vishal Kumar**, [SAP Community profile](https://profile.sap.com/u/iamvishalkumar)

---

## Debug ABAP with Claude

![ZGCTS_EXPORT + Claude: from an exported ABAP package to incident analysis](docs/zgcts_claude_integration.png)

1. **Export.** ZGCTS_EXPORT writes the whole package as text: one file per method, the dictionary data as JSON, and one Git commit per transport request.
2. **Understand.** Claude (Claude Code, started in the repository folder) reads the export once and builds a **knowledge graph**: who calls what, which tables are read and written, which statements raise which messages, and what each status value means.
3. **Debug by asking.** For each incident, Claude traces the symptom to its root cause with a file and line for every step, and lists the few checks to run on the system (SE16, SM37, ST22) instead of a debugging session.

In my own support work, this has cut the time from ticket to confirmed root cause by close to 90%. Most of that time used to go into searching, tracing call paths and debugging, not into the fix itself.

**Get started:** [docs/ai-assisted-debugging.md](docs/ai-assisted-debugging.md) contains the setup, the prompt that builds the knowledge graph, the 7-step incident analysis process and the guardrails. A ready-to-copy `CLAUDE.md` is in [docs/CLAUDE.template.md](docs/CLAUDE.template.md).

---

## What you get

```
<root>/
├── .gcts.properties.json
├── README.md
├── .zgcts/export.json                     ← export manifest
└── objects/
    ├── CLAS/
    │   └── ZCL_DEMO_ORDER/
    │       ├── CLAS ZCL_DEMO_ORDER.asx.json   ← SEOCLASS, SEOCOMPO, TMDIR, TADIR, ... as JSON
    │       ├── CLSD ZCL_DEMO_ORDER.abap       ← class definition
    │       ├── CPUB ZCL_DEMO_ORDER.abap       ← public section
    │       ├── CPRO ZCL_DEMO_ORDER.abap       ← protected section
    │       ├── CPRI ZCL_DEMO_ORDER.abap       ← private section
    │       ├── METH CREATE.abap               ← one file per method
    │       └── METH ZIF_DEMO_ORDER%7EGET.abap
    ├── DOMA/ ...                              ← fixed values: what a status code means
    ├── MSAG/ ...                              ← every message text and number
    ├── FUGR/ ...
    ├── PROG/ ...
    ├── TABL/ ...                              ← fields, keys, foreign keys
    └── zdemo_api/                             ← subpackage
        └── CLAS/ ...
```

## Screenshots

| Selection screen | Result list (package `SAPBC_DATAMODEL`) |
|---|---|
| ![Selection screen](docs/selection-screen.png) | ![Result list](docs/execution-result.png) |

## Features

- **Folders by object type.** Open `TABL/` and you see only the tables of the package.
- **One file per class section and per method**, so a diff, or an AI's citation, points at exactly one method.
- **Dictionary data as JSON.** Field names, keys, domain fixed values, message texts and method includes are written as the table rows themselves, so nobody has to guess what a field or status means.
- **Two modes:**
  - *By package*: a full snapshot of a package, optionally with its subpackages.
  - *By transport request*: only the objects in a request and its tasks. Each changed part (a `LIMU` sub-object such as one method) is exported as the whole object it belongs to (its `R3TR` object), duplicates are removed, and anything that can't be mapped is reported, not silently dropped.
- **Exports from different systems can be diffed.** Files are UTF-8 with LF line endings and no BOM, the client field is dropped and `TADIR-SRCSYSTEM` is masked, so exports from DEV, QA and PROD don't differ just because of the system.
- **No business data.** Only source code and repository metadata are exported.
- **Safe on older releases.** Every metadata table and key field is checked against the dictionary before it is read. A table that doesn't exist on the system is skipped instead of causing a dump.
- **Simulation mode** runs the whole export and shows the result list without downloading anything.

## Installation

Use either option:

- **abapGit:** clone this repository into a package of your choice. The text elements are created from `src/zgcts_export.prog.xml`.
- **Copy and paste:** create report `ZGCTS_EXPORT` in SE38, paste `src/zgcts_export.prog.abap`, then create the text elements listed in [docs/text-elements.md](docs/text-elements.md).

Details: [docs/installation.md](docs/installation.md)

**Requirements:** ABAP 7.40 SP08 or later (the code uses inline declarations, constructor operators, `xsdbool` and the newer Open SQL syntax), and SAP GUI for the download.

## Documentation

| Document | Contents |
|---|---|
| [docs/ai-assisted-debugging.md](docs/ai-assisted-debugging.md) | **Using the export with Claude:** setup, knowledge graph, 7-step incident process, prompts, guardrails |
| [docs/CLAUDE.template.md](docs/CLAUDE.template.md) | Ready-to-copy `CLAUDE.md` for an export repository |
| [docs/installation.md](docs/installation.md) | Installing with abapGit or by copy and paste |
| [docs/usage.md](docs/usage.md) | Selection screen, result list, Git workflow |
| [docs/output-format.md](docs/output-format.md) | Repository layout, file names, the `.asx.json` format, the manifest |
| [docs/object-types.md](docs/object-types.md) | Supported object types and the tables exported for each |
| [docs/transport-mode.md](docs/transport-mode.md) | How changed parts in a transport request are mapped to whole objects |
| [docs/comparison-with-abapgit.md](docs/comparison-with-abapgit.md) | When to use this report and when to use abapGit |
| [docs/text-elements.md](docs/text-elements.md) | Program title, text symbols and selection texts |

## Known limitations

- **The output is for reading, not importing.** It looks like a gCTS repository, but there is no guarantee that gCTS or R3trans can import it.
- DDIC version fields contain the active value `A`, not the transport-internal `L`/`N`.
- `.gctsmetadata/nametabs` is not generated.
- Text pools are exported in the object's master language and the logon language only.
- Object types without a table mapping get only their `TADIR` entry and are flagged as `TADIR ONLY` in the result list.
- **Claude reads code, not runtime values.** AI-assisted analysis still needs someone to run the checks on the system. See the guardrails in [docs/ai-assisted-debugging.md](docs/ai-assisted-debugging.md).

## Disclaimer

This report only reads from the SAP system. As with any tool, try it on a development system first. It is provided as is, without warranty of any kind. Before you share an export with any AI service, check your company's policy on source code.

## License

[MIT](LICENSE) © 2026 Vishal Kumar
