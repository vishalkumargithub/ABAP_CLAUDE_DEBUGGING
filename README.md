# ZGCTS_EXPORT

**Export an ABAP package, or a single transport request, to a readable Git repository with folders by object type.**

ZGCTS_EXPORT is one standalone ABAP report. It does not depend on anything else and **never writes to the SAP system**. It reads a package (or a transport request) and downloads a ZIP file to your PC. The ZIP is laid out like a **gCTS repository** (JSON format, `formatVersion 6`), with folders for **package → object type → object**.

Written by **Vishal Kumar**, [SAP Community profile](https://profile.sap.com/u/iamvishalkumar)

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
    │       ├── CLAS ZCL_DEMO_ORDER.asx.json   ← SEOCLASS, SEOCOMPO, TADIR, ... as JSON
    │       ├── CLSD ZCL_DEMO_ORDER.abap       ← class definition
    │       ├── CPUB ZCL_DEMO_ORDER.abap       ← public section
    │       ├── CPRO ZCL_DEMO_ORDER.abap       ← protected section
    │       ├── CPRI ZCL_DEMO_ORDER.abap       ← private section
    │       ├── METH CREATE.abap               ← one file per method
    │       └── METH ZIF_DEMO_ORDER%7EGET.abap
    ├── DOMA/ ...
    ├── FUGR/ ...
    ├── PROG/ ...
    ├── TABL/ ...
    └── zdemo_api/                             ← subpackage
        └── CLAS/ ...
```

## Features

- **Folders by object type.** Open `TABL/` and you see only the tables of the package.
- **One file per class section and per method**, so a diff shows exactly which method changed.
- **Two modes:**
  - *By package*: a full snapshot of a package, optionally with its subpackages.
  - *By transport request*: only the objects in a request and its tasks. Each changed part (a `LIMU` sub-object such as one method) is exported as the whole object it belongs to (its `R3TR` object), duplicates are removed, and anything that can't be mapped is reported, not silently dropped.
- **Exports from different systems can be diffed.** Files are UTF-8 with LF line endings and no BOM, the client field is dropped and `TADIR-SRCSYSTEM` is masked, so exports from DEV, QA and PROD don't differ just because of the system.
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

## Disclaimer

This report only reads from the SAP system. As with any tool, try it on a development system first. It is provided as is, without warranty of any kind.

## License

[MIT](LICENSE) © 2026 Vishal Kumar
