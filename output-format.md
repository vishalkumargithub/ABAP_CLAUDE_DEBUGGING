# Output format

## Repository root

| File | Written | Contents |
|---|---|---|
| `.gcts.properties.json` | Package mode | gCTS repository properties: name, version, description, `repositoryLayout` (`format json`, `formatVersion 6`, `keepClient false`, `tableContent true`) |
| `README.md` | Package mode | Package name, description, source system and client, export date, layout notes, known differences from a real gCTS repository |
| `.zgcts/export.json` | Every export | Manifest: see below |
| `objects/...` | Every export | One folder per object |

## Object folders

```
objects/<PKGPATH>/<OBJTYPE>/<OBJNAME>/
```

- **`PKGPATH`** is empty for objects of the exported (root) package. For a subpackage it is the chain of folders down from the root, each named after the full package name in lower case, with `/` replaced by `#`. This matches abapGit's "full" folder logic. Example: `objects/#ns#api/#ns#api_outbound/CLAS/...`
- **`OBJTYPE`** is the `R3TR` object type: `CLAS`, `TABL`, `FUGR`, ...
- **`OBJNAME`** is the object name. In file and folder names, these characters are URL-encoded:

| Character | Encoded as |
|---|---|
| `%` | `%25` |
| `/` | `%2F` |
| `~` | `%7E` |
| `:` | `%3A` |

## Files per object type

| Type | Files |
|---|---|
| All types with a table mapping | `<TYPE> <NAME>.asx.json` |
| `CLAS` | `CLSD`, `CPUB`, `CPRO`, `CPRI` `<NAME>.abap`; `CINC <include>.abap` for the local definitions, local implementations, macros and test classes (`CCDEF`, `CCIMP`, `CCMAC`, `CCAU`); `REPS <class>CT.abap`; `METH <method>.abap` for each implemented method |
| `INTF` | `REPS` for the interface pool, the interface section and the `IT` include |
| `PROG` | `REPS <NAME>.abap`, `REPT <NAME>.asx.json` (text pool), and `DYNP <nnnn>.abap` + `DYNP <nnnn>.asx.json` for each screen except 1000 |
| `FUGR` | `FUGR <NAME>.asx.json`; `FUNC <fm>.abap` (body) and `FUNC <fm>.$.abap` (signature, rebuilt from `FUPARAREF`) for each function module; `REPS` + `REPT` for each other include; `DYNP` files for the screens |
| `DOCT` / `DOCV` / `DSYS` | `<TYPE> <NAME>.asx.json` (`DOKHL`, `DOKIL`, `TADIR`) and one `DOCU <id> <object> <lang> <type> <version>.txt` per language and version |
| `DDLS` | `DDLS <NAME>.asx.json`. The CDS source is in the `DDDDLSRC` rows |

Empty files are not written. For example, a class without local test classes has no `CCAU` file.

## The `.asx.json` format

The format is the same as gCTS uses:

```json
[
 {
  "table":"DD01L",
  "data":
  [
   {
    "DOMNAME":"ZDEMO_STATUS",
    "AS4LOCAL":"A",
    "DATATYPE":"CHAR",
    "LENG":1
   }
  ]
 },
 {
  "table":"TADIR",
  "data":
  [
   ...
  ]
 }
]
```

| Rule | Detail |
|---|---|
| Indent | One space per level, no space after the colon |
| Table order | Alphabetical, with `_` before letters (`TOBJ_ATTR` before `TOBJT`). `TADIR` sorts in its normal place |
| Empty tables | Not written. That is why the list of tables differs from object to object |
| Client | `MANDT` is dropped (`keepClient = false`) |
| `TADIR-SRCSYSTEM` | Masked as `...` so the file doesn't depend on the system it came from |
| Integers, NUMC | Unquoted numbers (`"DOKVERSION":1`, not `"0001"`). A NUMC longer than 18 digits stays a string |
| Packed, float, decfloat | Unquoted, with the minus sign in front |
| Date / time | `"YYYY-MM-DD"` / `"HH:MM:SS"` |
| Raw (hex) | Base64 string |
| Text | JSON-escaped string |

## Encoding

Every file is UTF-8 **without a BOM**, uses **LF** line endings and has **no newline at the end**. The files are encoded in ABAP (`CL_ABAP_CONV_OUT_CE`, codepage 4110) and packed into a ZIP (`CL_ABAP_ZIP`), so the PC's settings cannot change the bytes.

## Manifest: `.zgcts/export.json`

Package mode:

```json
{
  "exportedAt": "2026-10-08T14:32:10",
  "system": "DEV",
  "client": "100",
  "exportedBy": "DEVELOPER",
  "rootPackage": "ZDEMO",
  "source": "package",
  "objects": 412
}
```

Request mode also records the request details and the list of objects:

```json
{
  "exportedAt": "2026-10-08T14:32:10",
  "system": "DEV",
  "client": "100",
  "exportedBy": "DEVELOPER",
  "rootPackage": "ZDEMO",
  "source": "transport",
  "transport": {
    "id": "DEVK900123",
    "description": "Order release: add credit check",
    "owner": "DEVELOPER",
    "date": "2026-10-07"
  },
  "objects": 3,
  "objectList": [
    "CLAS ZCL_DEMO_ORDER",
    "MSAG ZDEMO",
    "TABL ZDEMO_ORDERS"
  ]
}
```

## Differences from a real gCTS repository

- DDIC version fields (`AS4LOCAL`) contain the active value `A`, not the transport-internal `L`/`N`.
- `.gctsmetadata/nametabs` is not generated.
- Text pools contain the master language and the logon language only.
- The output is for reading, reviewing and diffing. There is no guarantee that gCTS or R3trans can import it.
