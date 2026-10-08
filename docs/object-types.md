# Supported object types

For most workbench and DDIC types, the SOBJ tables (`OBJH`/`OBJS`/`OBJSL`) are empty, because R3trans handles these types without them. So the report declares in `LCL_META` which tables make up each object type. Before any table or key field is read, it is checked against `DD02L`/`DD03L`. If a table doesn't exist on the system, it is skipped instead of causing a dump.

The `TADIR` row is added to every object.

## Types with a table mapping (`LCL_META`)

| Type | Tables | Key field |
|---|---|---|
| `DEVC` | `TDEVC`, `TDEVCT` | `DEVCLASS` |
| `DOMA` | `DD01L`, `DD01T`, `DD07L`, `DD07T` | `DOMNAME` |
| `DTEL` | `DD04L`, `DD04T`, `DDTYPES` | `ROLLNAME` / `TYPENAME` |
| `TABL` | `DD02L`, `DD02T`, `DD03L`, `DD05S`, `DD08L`, `DD09L`, `DD12L`, `DD17S`, `DD35L`, `DD36M`, `DDTYPES` | `TABNAME` / `SQLTAB` / `TYPENAME` |
| `TTYP` | `DD40L`, `DD40T`, `DD42S`, `DD43T`, `DDTYPES` | `TYPENAME` |
| `VIEW` | `DD25L`, `DD25T`, `DD26S`, `DD27S`, `DD28J`, `DD28V`, `DD29L`, `DDTYPES` | `VIEWNAME` / `TYPENAME` |
| `ENQU` | `DD25L`, `DD25T`, `DD26S`, `DD27S` | `VIEWNAME` |
| `SHLP` | `DD30L`, `DD30T`, `DD31S`, `DD32S`, `DD33S` | `SHLPNAME` |
| `DDLS` | `DDDDLSRC`, `DDDDLSRCT`, `DDDDLSRC02BT`, `DDLDEPENDENCY` | `DDLNAME` |
| `CLAS` | `DDTYPES`, `SEOCLASS`, `SEOCLASSDF`, `SEOCLASSTX`, `SEOCOMPO`, `SEOCOMPODF`, `SEOCOMPOTX`, `SEOMETAREL`, `SEOREDEF`, `SEOSUBCO`, `SEOSUBCODF`, `SEOSUBCOTX`, `TMDIR`, plus `TRDIR` of the class pool | `CLSNAME` / `CLASSNAME` / `TYPENAME` |
| `INTF` | `DDTYPES`, `SEOCLASS`, `SEOCLASSDF`, `SEOCLASSTX`, `SEOCOMPO`, `SEOCOMPODF`, `SEOCOMPOTX`, `SEOMETAREL`, plus `TRDIR` of the interface pool | `CLSNAME` / `TYPENAME` |
| `PROG` | `TRDIR`, `TRDIRT` | `NAME` |
| `MSAG` | `T100`, `T100A`, `T100T`, `T100U` | `ARBGB` |
| `TRAN` | `TSTC`, `TSTCC`, `TSTCP`, `TSTCT`, `USOBX`, `USOB_SM` | `TCODE` / `NAME` |
| `XSLT` | `O2XSLTDESC`, `O2XSLTTEXT` | `XSLTDESC` |
| `PARA` | `TPARA`, `TPARAT` | `PARAMID` |
| `ENHO` | `ENHHEADER`, `ENHHEADERT`, `ENHOBJ` | `ENHNAME` |
| `ENHS` | `ENHSPOTHEADER`, `ENHSPOTHEADERT` | `ENHSPOTNAME` |
| `VCLS` | `VCLDIR`, `VCLDIRT`, `VCLMF`, `VCLSTRUC`, `VCLSTRUCT`, `VCLSTRUDEP` | `VCLNAME` |
| `SVIM` | `TVDIR` | `TABNAME` |
| `STCS` | `STC_SCN_ATTR`, `STC_SCN_HDR`, `STC_SCN_HDR_T`, `STC_SCN_TASKS` | `SCENARIO` |
| `PINF` | `INTF`, `INTFTEXT` | `INTFNAME` |
| `SUSO` | `TACTZ`, `TOBJ`, `TOBJT` | `BROBJ` / `OBJCT` / `OBJECT` |

## Types built file by file (`LCL_SRC`)

The tables of these types are keyed by include, function module or document, not by the object name. So they get their own code that builds all their files, metadata included.

| Type | Tables and files |
|---|---|
| `FUGR` | `TLIBG`, `TLIBT` (by function group); `ENLFDIR`, `FUNCT`, `FUPARAREF`, `TFDIR`, `TFTIT` (by function module); `TRDIR`, `TRDIRT` (by include); `TADIR`. Plus a source file and a signature file per function module, a source file and text pool per include, and screens |
| `DOCT` | `DOKHL`, `DOKIL`, `TADIR`, plus documentation texts (ID `TX`) |
| `DOCV` | Same as `DOCT`. The 2-character documentation ID is the start of the object name |
| `DSYS` | Same as `DOCT`, with ID `HY` |

## Screens

For `PROG` and `FUGR`, each screen except selection screen 1000 is exported with:
- its flow logic, read with `RPY_DYNPRO_READ`
- the rows of `D020S`, `D020T`, `D021S`, `D021T`, `D022S` and `D023S` for that program and screen number

## Other types

An object type that is not listed above is still exported. It gets its `TADIR` row and status `TADIR ONLY`, so you can see in the result list which types need a mapping. To add a type, add `add( ... )` lines to `LCL_META=>CLASS_CONSTRUCTOR` (one line per table, with its key field), and add source handling in `LCL_SRC` if the type has ABAP source code.
