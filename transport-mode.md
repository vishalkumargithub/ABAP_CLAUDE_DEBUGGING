# Transport request mode

A transport request lists its objects in `E071`. Usually they are on the request's **tasks**, not on the request itself, and most of them are **`LIMU` sub-objects**, meaning parts of an object. A changed method appears as `LIMU METH`, not as `R3TR CLAS`. A repository stores whole objects, so each part has to be mapped to the whole (`R3TR`) object it belongs to before it can be exported.

## Steps

1. Read the request and all its tasks from `E070` (`TRKORR = request OR STRKORR = request`).
2. Read all their entries from `E071`.
3. Map each entry to its `R3TR` object, using the table below.
4. Look up the object's package in `TADIR`. The package decides which folder the object goes into.
5. Sort the objects and remove duplicates, so ten changed methods of one class produce one class export.
6. Export each object exactly as a package export would.

## How parts are mapped to whole objects

| `E071` entry | Exported as | How |
|---|---|---|
| `R3TR *` | Itself | No mapping needed |
| `LIMU CLSD`, `CPUB`, `CPRO`, `CPRI`, `CINC`, `METH`, `CLSC`, `CDEF`, `CIMP`, `CMAC`, `CAUS`, `CLLI`, `CPRV`, `CDER` | `CLAS` | The class name is in the first 30 characters (padded with spaces or `=`) |
| `LIMU INTD`, `INTC` | `INTF` | Same as for classes |
| `LIMU FUNC` | `FUGR` | `TFDIR-PNAME` (`SAPLZFOO` → `ZFOO`, `/NS/SAPLFOO` → `/NS/FOO`) |
| `LIMU REPS`, `REPT`, `DYNP`, `CUAD`, `DOCU` | `PROG`, or `FUGR` | `PROG` if a `TADIR` entry for a program with that name exists. Otherwise, the function group of the main program in `D010INC`, if that main program is `SAPL…` |
| `LIMU TABD`, `TABT`, `INDX`, `SQLT` | `TABL` | First 30 characters |
| `LIMU DOMD` | `DOMA` | Same name |
| `LIMU DTED` | `DTEL` | Same name |
| `LIMU VIED` | `VIEW` | Same name |
| `LIMU SHLD` | `SHLP` | Same name |
| `LIMU ENQD` | `ENQU` | Same name |
| `LIMU TTYD` | `TTYP` | Same name |
| `LIMU MESS` | `MSAG` | Message class = first 20 characters |
| Anything else | Not exported | Logged as `UNRESOLVED` |

## Nothing is dropped silently

Some entries can't be exported: either they can't be mapped to an object (`UNRESOLVED`), or the object has no `TADIR` entry (`NO TADIR`). These entries still appear in the result list with a reason. That way, a request never looks fully exported when part of it was skipped.

## Folder paths for a request export

If you leave the package field empty, each object's folder path is built by walking up `TDEVC` from the object's package to the top. If you enter the **root package** of your full export, the path stops at that package. The changed objects then land in exactly the same folders as in the full export, and you can unzip the request export over a clone of the full export.
