# ZGCTS_EXPORT and abapGit

**ZGCTS_EXPORT does not replace abapGit.** abapGit can import code back into a system, supports far more object types and has a large community behind it. Its file format is the standard for open-source ABAP. ZGCTS_EXPORT only exports code, so that you can **read, review and diff** it. This comparison is about that use case only.

| | abapGit | ZGCTS_EXPORT |
|---|---|---|
| **Folder layout** | One folder per package; objects side by side, told apart by file extension (`zcl_x.clas.abap`, `zcl_x.clas.xml`, `ztab.tabl.xml`, ...) | Package → **object type** → object folder |
| **Large packages** | One long list of files | Open `TABL/`, `CLAS/`, `FUGR/` ... and see only that object type |
| **Class source** | One `.clas.abap` file per class | Separate files for the definition, each section, each local include and **each method** |
| **Metadata** | abapGit XML | gCTS `.asx.json` (format version 6): the dictionary and repository table rows themselves |
| **Transport request as input** | Package-based workflow | Built-in request mode: changed parts are mapped to whole objects, duplicates removed, anything unmapped is reported |
| **Code size** | Standalone report is very large | One report, about 2,700 lines, no dependencies |
| **Changes the SAP system** | Yes (pull/deserialize) | **Never.** Only reads |
| **Import back into SAP** | ✅ Yes | ❌ No, export only |
| **Object types** | Very many | The common workbench and DDIC types (see [object-types.md](object-types.md)) |

## When to use which

Use **abapGit** to:
- move code between systems
- share and install open-source ABAP projects
- develop with code going both ways between SAP and Git

Use **ZGCTS_EXPORT** to:
- get a readable copy of a package, organized by object type
- review code in an IDE or a pull request, where each method is its own diff
- see what your code base would look like in gCTS before you migrate
- compare the same package across DEV, QA and PROD
- keep a Git history with one commit per transport request
- feed a code base to search or AI tools
- export from a system where a small, read-only report is easier to get approved than a full Git client
