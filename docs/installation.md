# Installation

## Option 1: abapGit

1. In abapGit, choose **New Online** (or **New Offline** and upload a ZIP of this repository).
2. Use a package of your own, for example `$ZGCTS` for a local install or a transportable `Z` package.
3. **Pull.** abapGit creates report `ZGCTS_EXPORT` together with its title, text symbols and selection texts.
4. Activate if abapGit asks you to.

Only `src/` is installed. `README.md`, `docs/` and the Git config files are ignored through `.abapgit.xml`.

## Option 2: Copy and paste

1. **SE38** → create report `ZGCTS_EXPORT`:
   - Type: *Executable program*
   - Title: `Export ABAP package to gCTS-shaped repository on frontend`
   - Unicode checks active: yes
2. Paste the full contents of [`src/zgcts_export.prog.abap`](../src/zgcts_export.prog.abap) and save.
3. *Goto → Text Elements*: create the text symbols and selection texts listed in [text-elements.md](text-elements.md).
4. Activate the report and the text elements.

If you skip step 3, the report still works, but the selection-screen frames have no titles and the parameters show their technical names (`P_DEVC`, `P_PATH`, ...).

## Requirements

| | |
|---|---|
| ABAP release | 7.40 SP08 or later |
| Frontend | SAP GUI, because the ZIP is downloaded with `CL_GUI_FRONTEND_SERVICES` |
| Authorizations | Read access to the repository and dictionary tables (`TADIR`, `DD*`, `SEO*`, `TFDIR`, `E070`/`E071`, ...) and permission to download files through SAP GUI |

The report runs no `INSERT`, `UPDATE`, `MODIFY` or `DELETE` on any database table, and it never calls a function module that changes repository objects.
