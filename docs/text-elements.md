# Text elements

The report needs one title, three text symbols and eleven selection texts. They are also listed in the header comment of `src/zgcts_export.prog.abap`.

- **abapGit** creates them automatically from `src/zgcts_export.prog.xml`.
- **Copy and paste into SE38:** create them by hand under *Goto → Text Elements*, then activate.

## Title

*Goto → Attributes → Title*

| Title |
|---|
| Export ABAP package to gCTS-shaped repository on frontend |

## Text symbols

*Goto → Text Elements → Text Symbols*. Each one is used as a selection-screen frame title.

| Sym | Text | Used by |
|---|---|---|
| `T01` | Source package | Block `B1`: export mode, package, transport request |
| `T02` | Target repository | Block `B2`: target folder, repository name and description |
| `T03` | Options | Block `B3`: metadata, source, simulation |

## Selection texts

*Goto → Text Elements → Selection Texts*. Selection texts can be at most 30 characters long. None of these use the "Dictionary Ref." option.

| Parameter | Text | Meaning |
|---|---|---|
| `P_BYPKG` | Export by package | Radio button: export a whole package |
| `P_BYTR` | Export by transport request | Radio button: export only the objects in a transport request |
| `P_DEVC` | Package | Package to export. In request mode it is optional and only decides the folder paths, so a request export lines up with a full export |
| `P_SUB` | Include subpackages | Also export the subpackages, as subfolders |
| `P_TRKORR` | Transport request | Request to export (request mode). Its tasks are included automatically |
| `P_PATH` | Target folder on PC | Folder the ZIP is downloaded to. F4 opens a folder picker |
| `P_NAME` | Repository name | Written to `.gcts.properties.json`. Default: package name in lower case |
| `P_DESC` | Repository description | Written to `.gcts.properties.json` and `README.md`. Default: package description |
| `P_META` | Write metadata (.asx.json) | Export the dictionary and repository table rows |
| `P_SRC` | Write source code (.abap) | Export the ABAP source code |
| `P_DRY` | Simulation, no download | Run everything and show the result list, but do not download the ZIP |
