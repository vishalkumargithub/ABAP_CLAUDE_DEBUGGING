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
| `T01` | Source Package | Block `B1`: export mode, package, transport request |
| `T02` | Target Repository | Block `B2`: target folder, repository name and description |
| `T03` | Options | Block `B3`: metadata, source, simulation |

## Selection texts

*Goto → Text Elements → Selection Texts*. Selection texts can be at most 30 characters long. None of these use the "Dictionary Ref." option.

| Parameter | Text | Meaning |
|---|---|---|
| `P_BYPKG` | Export the whole package | Radio button: export a whole package |
| `P_BYTR` | Export a TR | Radio button: export only the objects in a transport request |
| `P_DEVC` | Root Package | Package to export. In request mode it is optional and only decides the folder paths, so a request export lines up with a full export |
| `P_SUB` | Include SubPackages | Also export the subpackages, as subfolders |
| `P_TRKORR` | Transport Request | Request to export (request mode). Its tasks are included automatically |
| `P_PATH` | Frontend Download Folder | Folder the ZIP is downloaded to. F4 opens a folder picker |
| `P_NAME` | Repository Name | Written to `.gcts.properties.json`. Default: package name in lower case |
| `P_DESC` | Repository Description | Written to `.gcts.properties.json` and `README.md`. Default: package description |
| `P_META` | Write Metadata (.asx.json) | Export the dictionary and repository table rows |
| `P_SRC` | Write ABAP Source Files | Export the ABAP source code |
| `P_DRY` | Simulate | Run everything and show the result list, but do not download the ZIP |
