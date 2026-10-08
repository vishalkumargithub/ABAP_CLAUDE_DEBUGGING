*&---------------------------------------------------------------------*
*& Report ZGCTS_EXPORT
*& Title  : Export ABAP package to gCTS-shaped repository on frontend
*&---------------------------------------------------------------------*
*& This code was written by Vishal Kumar
*&   https://profile.sap.com/u/iamvishalkumar
*&---------------------------------------------------------------------*
*& Text elements
*&
*& The report needs the text elements below. abapGit creates them from
*& zgcts_export.prog.xml. When you paste the source into SE38 instead,
*& create them under Goto > Text Elements and activate them there.
*&
*&   Title (Goto > Attributes)
*&     Export ABAP package to gCTS-shaped repository on frontend
*&
*&   Text symbols                  Selection texts
*&     T01  Source package           P_BYPKG   Export by package
*&     T02  Target repository        P_BYTR    Export by transport request
*&     T03  Options                  P_DEVC    Package
*&                                   P_SUB     Include subpackages
*&                                   P_TRKORR  Transport request
*&                                   P_PATH    Target folder on PC
*&                                   P_NAME    Repository name
*&                                   P_DESC    Repository description
*&                                   P_META    Write metadata (.asx.json)
*&                                   P_SRC     Write source code (.abap)
*&                                   P_DRY     Simulation, no download
*&---------------------------------------------------------------------*
*& Exports an ABAP package to a gCTS-shaped repository on the frontend.
*&
*& Produces the layout of a gCTS repository with
*&   repositoryLayout.format = "json", formatVersion = "6":
*&
*&   <root>/.gcts.properties.json
*&   <root>/README.md
*&   <root>/objects/<PKGPATH>/<OBJTYPE>/<OBJNAME>/<OBJTYPE> <NAME>.asx.json
*&   <root>/objects/<PKGPATH>/<OBJTYPE>/<OBJNAME>/<PART> <NAME>.abap
*&
*& PKGPATH mirrors the package hierarchy using abapGit's naming (full
*& package name, lower case, "/" as "#"), so subpackage objects stay
*& together instead of piling into one CLAS folder. Objects of the
*& exported package itself sit directly under objects/.
*&
*& Files are written UTF-8, LF, without BOM, so the result diffs and
*& reads like a real gCTS repository checkout.
*&
*& Standalone: no abapGit dependency, read-only on the SAP side.
*&
*& Deliberate deviations from real gCTS output (see README):
*&  - DDIC version fields (AS4LOCAL) carry the active-version value 'A'
*&    rather than the transport-internal 'L'/'N'.
*&  - Nametabs (.gctsmetadata/nametabs) are not generated.
*&  - Output is not guaranteed to be importable by gCTS/R3trans.
*&---------------------------------------------------------------------*
REPORT zgcts_export LINE-SIZE 210.

CONSTANTS gc_srcsystem_mask TYPE string VALUE '...'.
CONSTANTS gc_lf             TYPE c LENGTH 1 VALUE cl_abap_char_utilities=>newline.

TYPES:
  BEGIN OF ty_obj,
    object   TYPE tadir-object,
    obj_name TYPE tadir-obj_name,
    devclass TYPE tadir-devclass,
  END OF ty_obj,
  tt_obj TYPE STANDARD TABLE OF ty_obj WITH EMPTY KEY.

TYPES tt_devc TYPE STANDARD TABLE OF devclass WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_map,
    object  TYPE trobjtype,   " transport object type, e.g. 'TABL'
    seqnr   TYPE i,           " keeps the gCTS table order stable
    tabname TYPE tabname,     " table to serialize
    keyfld  TYPE fieldname,   " field that carries the object name
  END OF ty_map,
  tt_map TYPE STANDARD TABLE OF ty_map WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_log,
    object   TYPE trobjtype,
    obj_name TYPE sobj_name,
    tables   TYPE i,
    files    TYPE i,
    status   TYPE string,
    message  TYPE string,
  END OF ty_log,
  tt_log TYPE STANDARD TABLE OF ty_log WITH EMPTY KEY.

" TEXTPOOLT as gCTS writes it (REPT <name>.asx.json)
TYPES:
  BEGIN OF ty_textpoolt,
    id     TYPE c LENGTH 1,
    key    TYPE c LENGTH 8,
    lang   TYPE c LENGTH 1,
    entry  TYPE c LENGTH 255,
    length TYPE i,
  END OF ty_textpoolt,
  tt_textpoolt TYPE STANDARD TABLE OF ty_textpoolt WITH EMPTY KEY.

*&---------------------------------------------------------------------*
*& Selection screen
*&---------------------------------------------------------------------*
" frame titles are filled at INITIALIZATION so the report needs no
" text elements to look right after a fresh import
DATA gv_t01 TYPE c LENGTH 60.
DATA gv_t02 TYPE c LENGTH 60.
DATA gv_t03 TYPE c LENGTH 60.
" gv_t01 = 'Source package'.
*  gv_t02 = 'Target repository'.
*  gv_t03 = 'Options'.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-t01.
  " Pick the source: the two modes are alternatives, and the rule for
  " each is enforced in AT SELECTION-SCREEN.
  "
  " Every field here stays enterable on purpose. Greying out the field
  " that does not belong to the chosen mode needs USER-COMMAND on the
  " radio group, and that round trip runs the automatic input checks. As
  " soon as one of those fails, P_PATH being OBLIGATORY is enough, the
  " screen comes back with only the complaining field ready for input,
  " which overrides AT SELECTION-SCREEN OUTPUT and leaves the transport
  " request permanently uneditable. No dynamic screen, no deadlock.
  "
  " P_DEVC has no OBLIGATORY flag for the same family of reasons: a
  " request export may legitimately leave it empty.
  PARAMETERS p_bypkg  RADIOBUTTON GROUP src DEFAULT 'X'.
  PARAMETERS p_bytr   RADIOBUTTON GROUP src.
  SELECTION-SCREEN SKIP.
  " exporting a package this is the scope; exporting a request it is the
  " repository root that keeps a delta's folder paths lined up with the
  " full export's, and it may be left blank
  PARAMETERS p_devc   TYPE devclass MEMORY ID dev.
  PARAMETERS p_sub    AS CHECKBOX DEFAULT 'X'.
  PARAMETERS p_trkorr TYPE trkorr.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-t02.
  PARAMETERS p_path TYPE string OBLIGATORY LOWER CASE.
  PARAMETERS p_name TYPE string LOWER CASE.
  PARAMETERS p_desc TYPE string LOWER CASE.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-t03.
  PARAMETERS p_meta AS CHECKBOX DEFAULT 'X'.
  PARAMETERS p_src  AS CHECKBOX DEFAULT 'X'.
  PARAMETERS p_dry  AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b3.

*&---------------------------------------------------------------------*
*& LCL_JSON - writes the exact gCTS .asx.json dialect
*&
*& [
*&  {
*&   "table":"DD01L",
*&   "data":
*&   [
*&    {
*&     "DOMNAME":"ALTINP",
*&     "LENG":1
*&    }
*&   ]
*&  }
*& ]
*&
*& One-space indent steps, no blank after the colon, numbers unquoted,
*& DATS as YYYY-MM-DD, TIMS as HH:MM:SS. Empty tables are omitted, which
*& is why the table list differs from object to object.
*&---------------------------------------------------------------------*
CLASS lcl_json DEFINITION CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS add_table
      IMPORTING iv_table TYPE tabname
                ir_data  TYPE REF TO data.

    METHODS is_empty
      RETURNING VALUE(rv_empty) TYPE abap_bool.

    METHODS render
      RETURNING VALUE(rt_lines) TYPE string_table.

    CLASS-METHODS escape
      IMPORTING iv_in         TYPE string
      RETURNING VALUE(rv_out) TYPE string.

  PRIVATE SECTION.
    " one entry per serialized table, already rendered
    DATA mt_sections TYPE TABLE OF string_table WITH EMPTY KEY.

    METHODS render_row
      IMPORTING is_row          TYPE any
                it_comp         TYPE abap_component_tab
      RETURNING VALUE(rt_lines) TYPE string_table.

    METHODS format_value
      IMPORTING iv_value      TYPE any
                io_type       TYPE REF TO cl_abap_datadescr
      RETURNING VALUE(rv_out) TYPE string.

    "! Moves a trailing minus to the front. The default conversion of a
    "! packed value writes the sign on the right, and JSON needs it left.
    CLASS-METHODS sign_left
      IMPORTING iv_in         TYPE string
      RETURNING VALUE(rv_out) TYPE string.

ENDCLASS.

CLASS lcl_json IMPLEMENTATION.

  METHOD is_empty.
    rv_empty = boolc( mt_sections IS INITIAL ).
  ENDMETHOD.

  METHOD escape.

    " the backslash must be doubled first, otherwise the escapes
    " introduced below would be escaped a second time
    CONSTANTS lc_bs TYPE c LENGTH 1 VALUE '\'.
    DATA lv_double TYPE string.

    lv_double = lc_bs && lc_bs.

    rv_out = iv_in.
    REPLACE ALL OCCURRENCES OF lc_bs IN rv_out WITH lv_double.
    REPLACE ALL OCCURRENCES OF '"' IN rv_out WITH '\"'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN rv_out WITH '\n'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN rv_out WITH '\n'.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>horizontal_tab IN rv_out WITH '\t'.
  ENDMETHOD.

  METHOD sign_left.

    rv_out = iv_in.
    CONDENSE rv_out.

    DATA(lv_len) = strlen( rv_out ).

    IF lv_len > 1 AND substring( val = rv_out off = lv_len - 1 len = 1 ) = '-'.
      rv_out = |-{ substring( val = rv_out len = lv_len - 1 ) }|.
    ENDIF.

  ENDMETHOD.

  METHOD format_value.

    CASE io_type->type_kind.

      WHEN cl_abap_typedescr=>typekind_int
        OR cl_abap_typedescr=>typekind_int1
        OR cl_abap_typedescr=>typekind_int2
        OR cl_abap_typedescr=>typekind_int8
        OR cl_abap_typedescr=>typekind_num.
        " IV_VALUE is TYPE ANY and a string template takes no formatting
        " option on a generic operand, so the value goes through a typed
        " helper. No NUMBER option: it is rejected on I, INT8 and P, and
        " integers convert without a thousands separator anyway.
        " NUMC belongs here because gCTS writes "DOKVERSION":1, not "0001".
        DATA lv_int TYPE int8.
        TRY.
            lv_int = iv_value.
            rv_out = sign_left( |{ lv_int }| ).
          CATCH cx_sy_conversion_error.
            " a NUMC wider than 18 digits is not a number we can trust
            DATA lv_raw TYPE string.
            lv_raw = iv_value.
            rv_out = |"{ escape( lv_raw ) }"|.
        ENDTRY.

      WHEN cl_abap_typedescr=>typekind_packed
        OR cl_abap_typedescr=>typekind_float
        OR cl_abap_typedescr=>typekind_decfloat16
        OR cl_abap_typedescr=>typekind_decfloat34.
        DATA lv_dec TYPE decfloat34.
        lv_dec = iv_value.
        rv_out = sign_left( |{ lv_dec }| ).

      WHEN cl_abap_typedescr=>typekind_date.
        DATA lv_d TYPE c LENGTH 8.
        lv_d = iv_value.
        rv_out = |"{ lv_d(4) }-{ lv_d+4(2) }-{ lv_d+6(2) }"|.

      WHEN cl_abap_typedescr=>typekind_time.
        DATA lv_t TYPE c LENGTH 6.
        lv_t = iv_value.
        rv_out = |"{ lv_t(2) }:{ lv_t+2(2) }:{ lv_t+4(2) }"|.

      WHEN cl_abap_typedescr=>typekind_hex.
        DATA lv_x TYPE xstring.
        DATA lv_b64 TYPE string.
        lv_x = iv_value.
        IF lv_x IS INITIAL.
          rv_out = '""'.
        ELSE.
          CALL FUNCTION 'SCMS_BASE64_ENCODE_STR'
            EXPORTING
              input  = lv_x
            IMPORTING
              output = lv_b64.
          rv_out = |"{ lv_b64 }"|.
        ENDIF.

      WHEN OTHERS.
        DATA lv_c TYPE string.
        lv_c = iv_value.
        " character fields keep their trailing blanks in transport data
        " only where they are part of the key; gCTS right-trims them
        rv_out = |"{ escape( lv_c ) }"|.

    ENDCASE.

  ENDMETHOD.

  METHOD render_row.

    DATA lv_line TYPE string.
    FIELD-SYMBOLS <lv_field> TYPE any.

    DATA(lv_last) = lines( it_comp ).

    LOOP AT it_comp INTO DATA(ls_comp).

      ASSIGN COMPONENT ls_comp-name OF STRUCTURE is_row TO <lv_field>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      lv_line = |    "{ ls_comp-name }":{ format_value( iv_value = <lv_field>
                                                        io_type  = ls_comp-type ) }|.
      IF sy-tabix < lv_last.
        lv_line = lv_line && ','.
      ENDIF.

      APPEND lv_line TO rt_lines.

    ENDLOOP.

  ENDMETHOD.

  METHOD add_table.

    FIELD-SYMBOLS <lt_data> TYPE ANY TABLE.

    ASSIGN ir_data->* TO <lt_data>.
    IF sy-subrc <> 0 OR <lt_data> IS INITIAL.
      RETURN.                          " gCTS omits tables without rows
    ENDIF.

    DATA(lo_tab)  = CAST cl_abap_tabledescr( cl_abap_typedescr=>describe_by_data_ref( ir_data ) ).
    DATA(lo_line) = lo_tab->get_table_line_type( ).
    IF lo_line->kind <> cl_abap_typedescr=>kind_struct.
      RETURN.
    ENDIF.

    DATA(lt_comp) = CAST cl_abap_structdescr( lo_line )->get_components( ).

    " keepClient = false -> the client field never reaches the repository
    DELETE lt_comp WHERE name = 'MANDT'.
    IF lt_comp IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_section TYPE string_table.

    APPEND ` {`                        TO lt_section.
    APPEND |  "table":"{ iv_table }",| TO lt_section.
    APPEND `  "data":`                 TO lt_section.
    APPEND `  [`                       TO lt_section.

    DATA(lv_rows) = lines( <lt_data> ).
    DATA lv_idx TYPE i.

    LOOP AT <lt_data> ASSIGNING FIELD-SYMBOL(<ls_row>).

      lv_idx = sy-tabix.

      APPEND `   {` TO lt_section.
      APPEND LINES OF render_row( is_row  = <ls_row>
                                  it_comp = lt_comp ) TO lt_section.
      IF lv_idx < lv_rows.
        APPEND `   },` TO lt_section.
      ELSE.
        APPEND `   }`  TO lt_section.
      ENDIF.

    ENDLOOP.

    APPEND `  ]` TO lt_section.
    APPEND ` }`  TO lt_section.

    APPEND lt_section TO mt_sections.

  ENDMETHOD.

  METHOD render.

    IF mt_sections IS INITIAL.
      RETURN.
    ENDIF.

    APPEND `[` TO rt_lines.

    DATA(lv_last) = lines( mt_sections ).

    LOOP AT mt_sections INTO DATA(lt_section).

      DATA(lv_i) = sy-tabix.

      IF lv_i < lv_last.
        " the closing " }" of a non-final section gets a comma
        DATA(lv_n) = lines( lt_section ).
        LOOP AT lt_section INTO DATA(lv_line).
          IF sy-tabix = lv_n.
            APPEND ` },` TO rt_lines.
          ELSE.
            APPEND lv_line TO rt_lines.
          ENDIF.
        ENDLOOP.
      ELSE.
        APPEND LINES OF lt_section TO rt_lines.
      ENDIF.

    ENDLOOP.

    APPEND `]` TO rt_lines.

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& LCL_FS - frontend filesystem writer
*&
*& Paths are handled internally with "/" and translated to the platform
*& separator on write. Content goes out as UTF-8 / LF / no BOM, which
*& GUI_DOWNLOAD only guarantees in binary mode, so every file is encoded
*& here and shipped as raw bytes.
*&---------------------------------------------------------------------*
CLASS lcl_fs DEFINITION CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING iv_root    TYPE string
                iv_zipname TYPE string
                iv_dry     TYPE abap_bool.

    "! No-op. A ZIP entry carries its own folder path, so there is
    "! nothing to create up front. Kept so the exporter reads naturally.
    METHODS mkdir
      IMPORTING iv_rel TYPE string.

    "! Adds a repository-relative text file to the archive: LF separated,
    "! no trailing LF, UTF-8 without BOM.
    METHODS write_text
      IMPORTING iv_rel       TYPE string
                it_lines     TYPE string_table
      RETURNING VALUE(rv_ok) TYPE abap_bool.

    "! Saves the archive and ships it to the frontend in a single round
    "! trip. Returns the path written, or empty when nothing was shipped.
    METHODS finalize
      RETURNING VALUE(rv_file) TYPE string.

    METHODS file_count
      RETURNING VALUE(rv_count) TYPE i.

    METHODS error_count
      RETURNING VALUE(rv_count) TYPE i.

  PRIVATE SECTION.
    DATA mv_root    TYPE string.
    DATA mv_zipname TYPE string.
    DATA mv_dry     TYPE abap_bool.
    DATA mv_sep     TYPE c LENGTH 1.
    DATA mv_files   TYPE i.
    DATA mv_errors  TYPE i.
    DATA mo_zip     TYPE REF TO cl_abap_zip.

    METHODS to_native
      IMPORTING iv_rel         TYPE string
      RETURNING VALUE(rv_path) TYPE string.

ENDCLASS.

CLASS lcl_fs IMPLEMENTATION.

  METHOD constructor.

    mv_root    = iv_root.
    mv_zipname = iv_zipname.
    mv_dry     = iv_dry.
    mo_zip     = NEW cl_abap_zip( ).

    " strip a trailing separator so joins stay predictable
    WHILE strlen( mv_root ) > 0
      AND ( substring( val = mv_root off = strlen( mv_root ) - 1 len = 1 ) = '\'
         OR substring( val = mv_root off = strlen( mv_root ) - 1 len = 1 ) = '/' ).
      mv_root = substring( val = mv_root len = strlen( mv_root ) - 1 ).
    ENDWHILE.

    cl_gui_frontend_services=>get_file_separator(
      CHANGING  file_separator = mv_sep
      EXCEPTIONS OTHERS        = 1 ).
    IF sy-subrc <> 0 OR mv_sep IS INITIAL.
      mv_sep = '\'.
    ENDIF.

  ENDMETHOD.

  METHOD file_count.
    rv_count = mv_files.
  ENDMETHOD.

  METHOD error_count.
    rv_count = mv_errors.
  ENDMETHOD.

  METHOD to_native.
    rv_path = |{ mv_root }/{ iv_rel }|.
    REPLACE ALL OCCURRENCES OF '/' IN rv_path WITH mv_sep.
  ENDMETHOD.

  METHOD mkdir.
    " intentionally empty, see the declaration
    RETURN.
  ENDMETHOD.

  METHOD write_text.

    DATA lv_content TYPE string.
    DATA lv_xstr    TYPE xstring.

    " gCTS files have no terminating newline
    CONCATENATE LINES OF it_lines INTO lv_content SEPARATED BY gc_lf.

    mv_files = mv_files + 1.
    rv_ok    = abap_true.

    IF mv_dry = abap_true.
      RETURN.
    ENDIF.

    " UTF-8 without BOM, and the LF separators above survive because the
    " bytes go into the archive untouched
    DATA(lo_conv) = cl_abap_conv_out_ce=>create( encoding = '4110' ).
    lo_conv->convert( EXPORTING data   = lv_content
                      IMPORTING buffer = lv_xstr ).

    " forward slashes are the ZIP path separator, so IV_REL goes in as is
    mo_zip->add( name    = iv_rel
                 content = lv_xstr ).

  ENDMETHOD.

  METHOD finalize.

    DATA lv_zip TYPE xstring.
    DATA lv_len TYPE i.
    DATA lt_bin TYPE solix_tab.

    rv_file = to_native( |{ mv_zipname }.zip| ).

    IF mv_dry = abap_true OR mv_files = 0.
      RETURN.
    ENDIF.

    lv_zip = mo_zip->save( ).

    CALL FUNCTION 'SCMS_XSTRING_TO_BINARY'
      EXPORTING
        buffer        = lv_zip
      IMPORTING
        output_length = lv_len
      TABLES
        binary_tab    = lt_bin.

    " the one and only frontend round trip of the whole export
    cl_gui_frontend_services=>gui_download(
      EXPORTING  bin_filesize = lv_len
                 filename     = rv_file
                 filetype     = 'BIN'
      CHANGING   data_tab     = lt_bin
      EXCEPTIONS OTHERS       = 1 ).

    IF sy-subrc <> 0.
      mv_errors = mv_errors + 1.
      CLEAR rv_file.
    ENDIF.

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& LCL_META - transport-object composition and generic table reader
*&
*& gCTS emits the tables of an object alphabetically, with TADIR taking
*& its normal place in that order, and it collates "_" before letters
*& (TOBJ_ATTR before TOBJT, USOB_SM before USOBX). SORTKEY reproduces
*& that by mapping "_" to a character below "A".
*&
*& Workbench and DDIC types are not described in the SOBJ tables
*& (OBJH/OBJS/OBJSL are empty for TABL, CLAS, PROG, ...) because R3trans
*& knows them natively, so the composition is declared here. Every table
*& and key field is validated against the dictionary before use, which
*& keeps the report safe across releases: an entry that does not fit the
*& system is skipped instead of dumping.
*&---------------------------------------------------------------------*
CLASS lcl_meta DEFINITION CREATE PRIVATE.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_pending,
        sortkey TYPE string,
        tabname TYPE tabname,
        data    TYPE REF TO data,
      END OF ty_pending,
      tt_pending TYPE STANDARD TABLE OF ty_pending WITH EMPTY KEY.

    CLASS-METHODS class_constructor.

    CLASS-METHODS tables_for
      IMPORTING iv_object     TYPE trobjtype
      RETURNING VALUE(rt_map) TYPE tt_map.

    CLASS-METHODS sortkey
      IMPORTING iv_table      TYPE tabname
      RETURNING VALUE(rv_key) TYPE string.

    "! Reads all rows of IV_TABLE whose IV_KEYFLD equals IV_VALUE.
    "! Returns an unbound reference when the table or the field does not
    "! exist, or when nothing was found, so callers can simply skip it.
    CLASS-METHODS read
      IMPORTING iv_table       TYPE tabname
                iv_keyfld      TYPE fieldname
                iv_value       TYPE clike
      RETURNING VALUE(rr_data) TYPE REF TO data.

    "! Same as READ, but with a caller supplied WHERE condition, for the
    "! tables whose key is not a single object name (screens, texts).
    CLASS-METHODS read_where
      IMPORTING iv_table       TYPE tabname
                iv_where       TYPE string
      RETURNING VALUE(rr_data) TYPE REF TO data.

    CLASS-METHODS read_tadir
      IMPORTING iv_object      TYPE trobjtype
                iv_obj_name    TYPE sobj_name
      RETURNING VALUE(rr_data) TYPE REF TO data.

    CLASS-METHODS quote
      IMPORTING iv_value      TYPE clike
      RETURNING VALUE(rv_out) TYPE string.

  PRIVATE SECTION.
    CLASS-DATA gt_map TYPE tt_map.
    CLASS-DATA gv_seq TYPE i.

    TYPES:
      BEGIN OF ty_cache,
        tabname TYPE tabname,
        fldname TYPE fieldname,
        ok      TYPE abap_bool,
      END OF ty_cache.
    CLASS-DATA gt_cache TYPE HASHED TABLE OF ty_cache
                          WITH UNIQUE KEY tabname fldname.

    CLASS-METHODS add
      IMPORTING iv_object TYPE trobjtype
                iv_table  TYPE tabname
                iv_keyfld TYPE fieldname.

    CLASS-METHODS is_usable
      IMPORTING iv_table     TYPE tabname
                iv_keyfld    TYPE fieldname
      RETURNING VALUE(rv_ok) TYPE abap_bool.

ENDCLASS.

CLASS lcl_meta IMPLEMENTATION.

  METHOD add.
    DATA ls_map TYPE ty_map.
    gv_seq          = gv_seq + 1.
    ls_map-object   = iv_object.
    ls_map-seqnr    = gv_seq.
    ls_map-tabname  = iv_table.
    ls_map-keyfld   = iv_keyfld.
    APPEND ls_map TO gt_map.
  ENDMETHOD.

  METHOD sortkey.
    rv_key = iv_table.
    REPLACE ALL OCCURRENCES OF '_' IN rv_key WITH '!'.
  ENDMETHOD.

  METHOD tables_for.
    LOOP AT gt_map INTO DATA(ls_map) WHERE object = iv_object.
      APPEND ls_map TO rt_map.
    ENDLOOP.
  ENDMETHOD.

  METHOD is_usable.

    READ TABLE gt_cache INTO DATA(ls_cache)
         WITH TABLE KEY tabname = iv_table fldname = iv_keyfld.
    IF sy-subrc = 0.
      rv_ok = ls_cache-ok.
      RETURN.
    ENDIF.

    ls_cache-tabname = iv_table.
    ls_cache-fldname = iv_keyfld.
    ls_cache-ok      = abap_false.

    SELECT SINGLE tabname FROM dd02l INTO @DATA(lv_tab)
      WHERE tabname  = @iv_table
        AND as4local = 'A'.

    IF sy-subrc = 0 AND lv_tab IS NOT INITIAL.
      SELECT SINGLE fieldname FROM dd03l INTO @DATA(lv_fld)
        WHERE tabname   = @iv_table
          AND fieldname = @iv_keyfld
          AND as4local  = 'A'.
      IF sy-subrc = 0 AND lv_fld IS NOT INITIAL.
        ls_cache-ok = abap_true.
      ENDIF.
    ENDIF.

    INSERT ls_cache INTO TABLE gt_cache.
    rv_ok = ls_cache-ok.

  ENDMETHOD.

  METHOD quote.
    DATA lv_val TYPE string.
    lv_val = iv_value.
    REPLACE ALL OCCURRENCES OF '''' IN lv_val WITH ''''''.
    CONCATENATE '''' lv_val '''' INTO rv_out.
  ENDMETHOD.

  METHOD read.

    DATA lv_where TYPE string.

    IF is_usable( iv_table = iv_table iv_keyfld = iv_keyfld ) = abap_false.
      RETURN.
    ENDIF.

    DATA(quoted_value) = quote( iv_value ).
    CONCATENATE iv_keyfld ' = ' quoted_value INTO lv_where.

    rr_data = read_where( iv_table = iv_table
                          iv_where = lv_where ).

  ENDMETHOD.

  METHOD read_where.

    FIELD-SYMBOLS <lt_data> TYPE STANDARD TABLE.

    TRY.
        CREATE DATA rr_data TYPE STANDARD TABLE OF (iv_table).
      CATCH cx_sy_create_data_error.
        CLEAR rr_data.
        RETURN.
    ENDTRY.

    ASSIGN rr_data->* TO <lt_data>.
    IF sy-subrc <> 0.
      CLEAR rr_data.
      RETURN.
    ENDIF.

    TRY.
        SELECT * FROM (iv_table)
          INTO TABLE <lt_data>
          WHERE (iv_where).
      CATCH cx_sy_dynamic_osql_error cx_sy_open_sql_db.
        CLEAR rr_data.
        RETURN.
    ENDTRY.

    IF <lt_data> IS INITIAL.
      CLEAR rr_data.
    ENDIF.

  ENDMETHOD.

  METHOD read_tadir.

    DATA lt_tadir TYPE STANDARD TABLE OF tadir WITH EMPTY KEY.
    FIELD-SYMBOLS <lt_out> TYPE STANDARD TABLE.

    SELECT * FROM tadir
      INTO TABLE @lt_tadir
      WHERE pgmid    = 'R3TR'
        AND object   = @iv_object
        AND obj_name = @iv_obj_name.

    IF lt_tadir IS INITIAL.
      RETURN.
    ENDIF.

    " gCTS keeps the repository free of the exporting system's name
    LOOP AT lt_tadir ASSIGNING FIELD-SYMBOL(<ls_tadir>).
      <ls_tadir>-srcsystem = gc_srcsystem_mask.
    ENDLOOP.

    CREATE DATA rr_data LIKE lt_tadir.
    ASSIGN rr_data->* TO <lt_out>.
    <lt_out> = lt_tadir.

  ENDMETHOD.

  METHOD class_constructor.

    " ---- packages --------------------------------------------------
    add( iv_object = 'DEVC' iv_table = 'TDEVC'  iv_keyfld = 'DEVCLASS' ).
    add( iv_object = 'DEVC' iv_table = 'TDEVCT' iv_keyfld = 'DEVCLASS' ).

    " ---- dictionary ------------------------------------------------
    add( iv_object = 'DOMA' iv_table = 'DD01L' iv_keyfld = 'DOMNAME' ).
    add( iv_object = 'DOMA' iv_table = 'DD01T' iv_keyfld = 'DOMNAME' ).
    add( iv_object = 'DOMA' iv_table = 'DD07L' iv_keyfld = 'DOMNAME' ).
    add( iv_object = 'DOMA' iv_table = 'DD07T' iv_keyfld = 'DOMNAME' ).

    add( iv_object = 'DTEL' iv_table = 'DD04L'   iv_keyfld = 'ROLLNAME' ).
    add( iv_object = 'DTEL' iv_table = 'DD04T'   iv_keyfld = 'ROLLNAME' ).
    add( iv_object = 'DTEL' iv_table = 'DDTYPES' iv_keyfld = 'TYPENAME' ).

    add( iv_object = 'TABL' iv_table = 'DD02L'   iv_keyfld = 'TABNAME' ).
    add( iv_object = 'TABL' iv_table = 'DD02T'   iv_keyfld = 'TABNAME' ).
    add( iv_object = 'TABL' iv_table = 'DD03L'   iv_keyfld = 'TABNAME' ).
    add( iv_object = 'TABL' iv_table = 'DD05S'   iv_keyfld = 'TABNAME' ).
    add( iv_object = 'TABL' iv_table = 'DD08L'   iv_keyfld = 'TABNAME' ).
    add( iv_object = 'TABL' iv_table = 'DD09L'   iv_keyfld = 'TABNAME' ).
    add( iv_object = 'TABL' iv_table = 'DD12L'   iv_keyfld = 'SQLTAB' ).
    add( iv_object = 'TABL' iv_table = 'DD17S'   iv_keyfld = 'SQLTAB' ).
    add( iv_object = 'TABL' iv_table = 'DD35L'   iv_keyfld = 'TABNAME' ).
    add( iv_object = 'TABL' iv_table = 'DD36M'   iv_keyfld = 'TABNAME' ).
    add( iv_object = 'TABL' iv_table = 'DDTYPES' iv_keyfld = 'TYPENAME' ).

    add( iv_object = 'TTYP' iv_table = 'DD40L'   iv_keyfld = 'TYPENAME' ).
    add( iv_object = 'TTYP' iv_table = 'DD40T'   iv_keyfld = 'TYPENAME' ).
    add( iv_object = 'TTYP' iv_table = 'DD42S'   iv_keyfld = 'TYPENAME' ).
    add( iv_object = 'TTYP' iv_table = 'DD43T'   iv_keyfld = 'TYPENAME' ).
    add( iv_object = 'TTYP' iv_table = 'DDTYPES' iv_keyfld = 'TYPENAME' ).

    add( iv_object = 'VIEW' iv_table = 'DD25L'   iv_keyfld = 'VIEWNAME' ).
    add( iv_object = 'VIEW' iv_table = 'DD25T'   iv_keyfld = 'VIEWNAME' ).
    add( iv_object = 'VIEW' iv_table = 'DD26S'   iv_keyfld = 'VIEWNAME' ).
    add( iv_object = 'VIEW' iv_table = 'DD27S'   iv_keyfld = 'VIEWNAME' ).
    add( iv_object = 'VIEW' iv_table = 'DD28J'   iv_keyfld = 'VIEWNAME' ).
    add( iv_object = 'VIEW' iv_table = 'DD28V'   iv_keyfld = 'VIEWNAME' ).
    add( iv_object = 'VIEW' iv_table = 'DD29L'   iv_keyfld = 'VIEWNAME' ).
    add( iv_object = 'VIEW' iv_table = 'DDTYPES' iv_keyfld = 'TYPENAME' ).

    add( iv_object = 'ENQU' iv_table = 'DD25L' iv_keyfld = 'VIEWNAME' ).
    add( iv_object = 'ENQU' iv_table = 'DD25T' iv_keyfld = 'VIEWNAME' ).
    add( iv_object = 'ENQU' iv_table = 'DD26S' iv_keyfld = 'VIEWNAME' ).
    add( iv_object = 'ENQU' iv_table = 'DD27S' iv_keyfld = 'VIEWNAME' ).

    add( iv_object = 'SHLP' iv_table = 'DD30L' iv_keyfld = 'SHLPNAME' ).
    add( iv_object = 'SHLP' iv_table = 'DD30T' iv_keyfld = 'SHLPNAME' ).
    add( iv_object = 'SHLP' iv_table = 'DD31S' iv_keyfld = 'SHLPNAME' ).
    add( iv_object = 'SHLP' iv_table = 'DD32S' iv_keyfld = 'SHLPNAME' ).
    add( iv_object = 'SHLP' iv_table = 'DD33S' iv_keyfld = 'SHLPNAME' ).

    add( iv_object = 'DDLS' iv_table = 'DDDDLSRC'      iv_keyfld = 'DDLNAME' ).
    add( iv_object = 'DDLS' iv_table = 'DDDDLSRCT'     iv_keyfld = 'DDLNAME' ).
    add( iv_object = 'DDLS' iv_table = 'DDDDLSRC02BT'  iv_keyfld = 'DDLNAME' ).
    add( iv_object = 'DDLS' iv_table = 'DDLDEPENDENCY' iv_keyfld = 'DDLNAME' ).

    " ---- object orientation ----------------------------------------
    add( iv_object = 'CLAS' iv_table = 'DDTYPES'    iv_keyfld = 'TYPENAME' ).
    add( iv_object = 'CLAS' iv_table = 'SEOCLASS'   iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'CLAS' iv_table = 'SEOCLASSDF' iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'CLAS' iv_table = 'SEOCLASSTX' iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'CLAS' iv_table = 'SEOCOMPO'   iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'CLAS' iv_table = 'SEOCOMPODF' iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'CLAS' iv_table = 'SEOCOMPOTX' iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'CLAS' iv_table = 'SEOMETAREL' iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'CLAS' iv_table = 'SEOREDEF'   iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'CLAS' iv_table = 'SEOSUBCO'   iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'CLAS' iv_table = 'SEOSUBCODF' iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'CLAS' iv_table = 'SEOSUBCOTX' iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'CLAS' iv_table = 'TMDIR'      iv_keyfld = 'CLASSNAME' ).

    add( iv_object = 'INTF' iv_table = 'DDTYPES'    iv_keyfld = 'TYPENAME' ).
    add( iv_object = 'INTF' iv_table = 'SEOCLASS'   iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'INTF' iv_table = 'SEOCLASSDF' iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'INTF' iv_table = 'SEOCLASSTX' iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'INTF' iv_table = 'SEOCOMPO'   iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'INTF' iv_table = 'SEOCOMPODF' iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'INTF' iv_table = 'SEOCOMPOTX' iv_keyfld = 'CLSNAME' ).
    add( iv_object = 'INTF' iv_table = 'SEOMETAREL' iv_keyfld = 'CLSNAME' ).

    " ---- programs, messages, transactions --------------------------
    add( iv_object = 'PROG' iv_table = 'TRDIR'  iv_keyfld = 'NAME' ).
    add( iv_object = 'PROG' iv_table = 'TRDIRT' iv_keyfld = 'NAME' ).

    add( iv_object = 'MSAG' iv_table = 'T100'  iv_keyfld = 'ARBGB' ).
    add( iv_object = 'MSAG' iv_table = 'T100A' iv_keyfld = 'ARBGB' ).
    add( iv_object = 'MSAG' iv_table = 'T100T' iv_keyfld = 'ARBGB' ).
    add( iv_object = 'MSAG' iv_table = 'T100U' iv_keyfld = 'ARBGB' ).

    add( iv_object = 'TRAN' iv_table = 'TSTC'    iv_keyfld = 'TCODE' ).
    add( iv_object = 'TRAN' iv_table = 'TSTCC'   iv_keyfld = 'TCODE' ).
    add( iv_object = 'TRAN' iv_table = 'TSTCP'   iv_keyfld = 'TCODE' ).
    add( iv_object = 'TRAN' iv_table = 'TSTCT'   iv_keyfld = 'TCODE' ).
    add( iv_object = 'TRAN' iv_table = 'USOBX'   iv_keyfld = 'NAME' ).
    add( iv_object = 'TRAN' iv_table = 'USOB_SM' iv_keyfld = 'NAME' ).

    add( iv_object = 'XSLT' iv_table = 'O2XSLTDESC' iv_keyfld = 'XSLTDESC' ).
    add( iv_object = 'XSLT' iv_table = 'O2XSLTTEXT' iv_keyfld = 'XSLTDESC' ).

    add( iv_object = 'PARA' iv_table = 'TPARA'  iv_keyfld = 'PARAMID' ).
    add( iv_object = 'PARA' iv_table = 'TPARAT' iv_keyfld = 'PARAMID' ).

    " ---- enhancements, view clusters, task lists -------------------
    add( iv_object = 'ENHO' iv_table = 'ENHHEADER'  iv_keyfld = 'ENHNAME' ).
    add( iv_object = 'ENHO' iv_table = 'ENHHEADERT' iv_keyfld = 'ENHNAME' ).
    add( iv_object = 'ENHO' iv_table = 'ENHOBJ'     iv_keyfld = 'ENHNAME' ).

    add( iv_object = 'ENHS' iv_table = 'ENHSPOTHEADER'  iv_keyfld = 'ENHSPOTNAME' ).
    add( iv_object = 'ENHS' iv_table = 'ENHSPOTHEADERT' iv_keyfld = 'ENHSPOTNAME' ).

    add( iv_object = 'VCLS' iv_table = 'VCLDIR'     iv_keyfld = 'VCLNAME' ).
    add( iv_object = 'VCLS' iv_table = 'VCLDIRT'    iv_keyfld = 'VCLNAME' ).
    add( iv_object = 'VCLS' iv_table = 'VCLMF'      iv_keyfld = 'VCLNAME' ).
    add( iv_object = 'VCLS' iv_table = 'VCLSTRUC'   iv_keyfld = 'VCLNAME' ).
    add( iv_object = 'VCLS' iv_table = 'VCLSTRUCT'  iv_keyfld = 'VCLNAME' ).
    add( iv_object = 'VCLS' iv_table = 'VCLSTRUDEP' iv_keyfld = 'VCLNAME' ).

    add( iv_object = 'SVIM' iv_table = 'TVDIR' iv_keyfld = 'TABNAME' ).

    add( iv_object = 'STCS' iv_table = 'STC_SCN_ATTR'  iv_keyfld = 'SCENARIO' ).
    add( iv_object = 'STCS' iv_table = 'STC_SCN_HDR'   iv_keyfld = 'SCENARIO' ).
    add( iv_object = 'STCS' iv_table = 'STC_SCN_HDR_T' iv_keyfld = 'SCENARIO' ).
    add( iv_object = 'STCS' iv_table = 'STC_SCN_TASKS' iv_keyfld = 'SCENARIO' ).

    add( iv_object = 'PINF' iv_table = 'INTF'     iv_keyfld = 'INTFNAME' ).
    add( iv_object = 'PINF' iv_table = 'INTFTEXT' iv_keyfld = 'INTFNAME' ).

    add( iv_object = 'SUSO' iv_table = 'TACTZ' iv_keyfld = 'BROBJ' ).
    add( iv_object = 'SUSO' iv_table = 'TOBJ'  iv_keyfld = 'OBJCT' ).
    add( iv_object = 'SUSO' iv_table = 'TOBJT' iv_keyfld = 'OBJECT' ).

    " FUGR, DOCT, DOCV and DSYS are composed per include or per document
    " and are handled by LCL_SRC / LCL_EXPORTER rather than by this map.

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& A file about to be written into an object folder
*&---------------------------------------------------------------------*
TYPES:
  BEGIN OF ty_file,
    name  TYPE string,
    lines TYPE string_table,
  END OF ty_file,
  tt_file TYPE STANDARD TABLE OF ty_file WITH EMPTY KEY.

*&---------------------------------------------------------------------*
*& LCL_SRC - source parts of the object types that carry ABAP text
*&
*& Types whose composition is per include or per document (FUGR, DOCT,
*& DOCV, DSYS) are produced here in full, metadata included, because
*& their tables are not keyed by the object name. HANDLES tells the
*& exporter which types take this path.
*&---------------------------------------------------------------------*
CLASS lcl_src DEFINITION CREATE PRIVATE.

  PUBLIC SECTION.

    CLASS-METHODS handles
      IMPORTING iv_object    TYPE trobjtype
      RETURNING VALUE(rv_ok) TYPE abap_bool.

    "! Source parts for the types the generic map already covers
    CLASS-METHODS source_files
      IMPORTING iv_object       TYPE trobjtype
                iv_obj_name     TYPE sobj_name
      RETURNING VALUE(rt_files) TYPE tt_file.

    "! Complete file set, metadata included, for the self contained types
    CLASS-METHODS composed_files
      IMPORTING iv_object       TYPE trobjtype
                iv_obj_name     TYPE sobj_name
      RETURNING VALUE(rt_files) TYPE tt_file.

    "! "/" and "~" cannot appear in a path, gCTS URL encodes them
    CLASS-METHODS encode
      IMPORTING iv_name       TYPE clike
      RETURNING VALUE(rv_out) TYPE string.

  PRIVATE SECTION.

    CLASS-METHODS read_src
      IMPORTING iv_prog         TYPE clike
      RETURNING VALUE(rt_lines) TYPE string_table.

    CLASS-METHODS add_file
      IMPORTING iv_name  TYPE string
                it_lines TYPE string_table
      CHANGING  ct_files TYPE tt_file.

    CLASS-METHODS class_files
      IMPORTING iv_class        TYPE sobj_name
      RETURNING VALUE(rt_files) TYPE tt_file.

    CLASS-METHODS intf_files
      IMPORTING iv_intf         TYPE sobj_name
      RETURNING VALUE(rt_files) TYPE tt_file.

    CLASS-METHODS prog_files
      IMPORTING iv_prog         TYPE sobj_name
      RETURNING VALUE(rt_files) TYPE tt_file.

    CLASS-METHODS textpool_file
      IMPORTING iv_prog     TYPE clike
                iv_filename TYPE string
      CHANGING  ct_files    TYPE tt_file.

    CLASS-METHODS fugr_files
      IMPORTING iv_area         TYPE sobj_name
      RETURNING VALUE(rt_files) TYPE tt_file.

    CLASS-METHODS docu_files
      IMPORTING iv_object       TYPE trobjtype
                iv_obj_name     TYPE sobj_name
      RETURNING VALUE(rt_files) TYPE tt_file.

    CLASS-METHODS dynpro_files
      IMPORTING iv_prog  TYPE clike
      CHANGING  ct_files TYPE tt_file.

    CLASS-METHODS func_interface
      IMPORTING iv_func         TYPE clike
      RETURNING VALUE(rt_lines) TYPE string_table.

    CLASS-METHODS split_area
      IMPORTING iv_area  TYPE clike
      EXPORTING ev_ns    TYPE string
                ev_short TYPE string.

    CLASS-METHODS collect
      IMPORTING ir_source TYPE REF TO data
      CHANGING  cr_target TYPE REF TO data.

ENDCLASS.

CLASS lcl_src IMPLEMENTATION.

  METHOD handles.
    rv_ok = xsdbool( iv_object = 'FUGR'
                  OR iv_object = 'DOCT'
                  OR iv_object = 'DOCV'
                  OR iv_object = 'DSYS' ).
  ENDMETHOD.

  METHOD encode.
    " assigning a character field to a string already drops the
    " trailing blanks of the 30 or 40 character key
    rv_out = iv_name.
    REPLACE ALL OCCURRENCES OF '%' IN rv_out WITH '%25'.
    REPLACE ALL OCCURRENCES OF '/' IN rv_out WITH '%2F'.
    REPLACE ALL OCCURRENCES OF '~' IN rv_out WITH '%7E'.
    REPLACE ALL OCCURRENCES OF ':' IN rv_out WITH '%3A'.
  ENDMETHOD.

  METHOD add_file.
    DATA ls_file TYPE ty_file.
    IF it_lines IS INITIAL.
      RETURN.
    ENDIF.
    ls_file-name  = iv_name.
    ls_file-lines = it_lines.
    APPEND ls_file TO ct_files.
  ENDMETHOD.

  METHOD read_src.

    DATA lv_prog TYPE program.

    lv_prog = iv_prog.
    IF lv_prog IS INITIAL.
      RETURN.
    ENDIF.

    READ REPORT lv_prog INTO rt_lines.
    IF sy-subrc <> 0.
      CLEAR rt_lines.
    ENDIF.

  ENDMETHOD.

  METHOD collect.

    FIELD-SYMBOLS <lt_src> TYPE STANDARD TABLE.
    FIELD-SYMBOLS <lt_tgt> TYPE STANDARD TABLE.

    IF ir_source IS NOT BOUND.
      RETURN.
    ENDIF.

    ASSIGN ir_source->* TO <lt_src>.
    IF sy-subrc <> 0 OR <lt_src> IS INITIAL.
      RETURN.
    ENDIF.

    IF cr_target IS NOT BOUND.
      CREATE DATA cr_target LIKE <lt_src>.
    ENDIF.

    ASSIGN cr_target->* TO <lt_tgt>.
    LOOP AT <lt_src> ASSIGNING FIELD-SYMBOL(<ls_row>).
      APPEND <ls_row> TO <lt_tgt>.
    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
* Source parts for the map driven types
*----------------------------------------------------------------------*
  METHOD source_files.

    CASE iv_object.
      WHEN 'CLAS'.
        rt_files = class_files( iv_obj_name ).
      WHEN 'INTF'.
        rt_files = intf_files( iv_obj_name ).
      WHEN 'PROG'.
        rt_files = prog_files( iv_obj_name ).
      WHEN OTHERS.
        " dictionary and customizing types have no ABAP text
    ENDCASE.

  ENDMETHOD.

  METHOD class_files.

    DATA lv_name TYPE string.
    " the four sections carry the plain class name in the file name
    lv_name = encode( iv_class ).

    add_file( EXPORTING iv_name  = |CLSD { lv_name }.abap|
                        it_lines = read_src( cl_oo_classname_service=>get_classpool_name( CONV #( iv_class ) ) )
              CHANGING  ct_files = rt_files ).

    add_file( EXPORTING iv_name  = |CPUB { lv_name }.abap|
                        it_lines = read_src( cl_oo_classname_service=>get_pubsec_name( CONV #( iv_class ) ) )
              CHANGING  ct_files = rt_files ).

    add_file( EXPORTING iv_name  = |CPRO { lv_name }.abap|
                        it_lines = read_src( cl_oo_classname_service=>get_prosec_name( CONV #( iv_class ) ) )
              CHANGING  ct_files = rt_files ).

    add_file( EXPORTING iv_name  = |CPRI { lv_name }.abap|
                        it_lines = read_src( cl_oo_classname_service=>get_prisec_name( CONV #( iv_class ) ) )
              CHANGING  ct_files = rt_files ).

    " local definition includes keep their generated include name
    DATA lt_cinc TYPE STANDARD TABLE OF program WITH EMPTY KEY.
    APPEND cl_oo_classname_service=>get_ccdef_name( CONV #( iv_class ) ) TO lt_cinc.
    APPEND cl_oo_classname_service=>get_ccimp_name( CONV #( iv_class ) ) TO lt_cinc.
    APPEND cl_oo_classname_service=>get_ccmac_name( CONV #( iv_class ) ) TO lt_cinc.
    APPEND cl_oo_classname_service=>get_ccau_name( CONV #( iv_class ) )  TO lt_cinc.

    LOOP AT lt_cinc INTO DATA(lv_cinc).
      add_file( EXPORTING iv_name  = |CINC { encode( lv_cinc ) }.abap|
                          it_lines = read_src( lv_cinc )
                CHANGING  ct_files = rt_files ).
    ENDLOOP.

    " the type dummy include travels as an ordinary report source
    DATA(lv_ct) = cl_oo_classname_service=>get_ct_name( CONV #( iv_class ) ).
    add_file( EXPORTING iv_name  = |REPS { encode( lv_ct ) }.abap|
                        it_lines = read_src( lv_ct )
              CHANGING  ct_files = rt_files ).

    " one file per implemented method, "~" URL encoded.
    " CALL METHOD because the service raises a classic exception
    DATA lt_meth    TYPE seop_methods_w_include.
    DATA lv_clsname TYPE seoclsname.

    lv_clsname = iv_class.

    CALL METHOD cl_oo_classname_service=>get_all_method_includes
      EXPORTING
        clsname            = lv_clsname
      RECEIVING
        result             = lt_meth
      EXCEPTIONS
        class_not_existing = 1
        OTHERS             = 2.
    IF sy-subrc <> 0.
      CLEAR lt_meth.
    ENDIF.

    LOOP AT lt_meth INTO DATA(ls_meth).
      add_file( EXPORTING iv_name  = |METH { encode( ls_meth-cpdkey-cpdname ) }.abap|
                          it_lines = read_src( ls_meth-incname )
                CHANGING  ct_files = rt_files ).
    ENDLOOP.

  ENDMETHOD.

  METHOD intf_files.

    DATA(lv_ip) = cl_oo_classname_service=>get_interfacepool_name( CONV #( iv_intf ) ).
    DATA(lv_iu) = cl_oo_classname_service=>get_intfsec_name( CONV #( iv_intf ) ).

    add_file( EXPORTING iv_name  = |REPS { encode( lv_ip ) }.abap|
                        it_lines = read_src( lv_ip )
              CHANGING  ct_files = rt_files ).

    add_file( EXPORTING iv_name  = |REPS { encode( lv_iu ) }.abap|
                        it_lines = read_src( lv_iu )
              CHANGING  ct_files = rt_files ).

    " IT is the type dummy include, built like the class CT include
    DATA lv_it TYPE program.
    lv_it = |{ iv_intf WIDTH = 30 PAD = '=' }IT|.

    add_file( EXPORTING iv_name  = |REPS { encode( lv_it ) }.abap|
                        it_lines = read_src( lv_it )
              CHANGING  ct_files = rt_files ).

  ENDMETHOD.

  METHOD prog_files.

    DATA(lv_name) = encode( iv_prog ).

    add_file( EXPORTING iv_name  = |REPS { lv_name }.abap|
                        it_lines = read_src( iv_prog )
              CHANGING  ct_files = rt_files ).

    textpool_file( EXPORTING iv_prog     = iv_prog
                             iv_filename = |REPT { lv_name }.asx.json|
                   CHANGING  ct_files    = rt_files ).

    dynpro_files( EXPORTING iv_prog  = iv_prog
                  CHANGING  ct_files = rt_files ).

  ENDMETHOD.

  METHOD textpool_file.

    DATA lt_tpool  TYPE STANDARD TABLE OF textpool WITH EMPTY KEY.
    DATA lt_out    TYPE tt_textpoolt.
    DATA ls_out    TYPE ty_textpoolt.
    DATA lr_out    TYPE REF TO data.
    DATA lv_prog   TYPE program.
    DATA lt_langu  TYPE STANDARD TABLE OF sy-langu WITH EMPTY KEY.

    lv_prog = iv_prog.

    " the text pool is only reachable per language, so the object's
    " master language and the logon language are both tried
    SELECT SINGLE masterlang FROM tadir INTO @DATA(lv_master)
      WHERE pgmid = 'R3TR' AND object = 'PROG' AND obj_name = @iv_prog.

    IF lv_master IS NOT INITIAL.
      APPEND lv_master TO lt_langu.
    ENDIF.
    IF sy-langu <> lv_master.
      APPEND sy-langu TO lt_langu.
    ENDIF.

    LOOP AT lt_langu INTO DATA(lv_langu).

      CLEAR lt_tpool.
      READ TEXTPOOL lv_prog INTO lt_tpool LANGUAGE lv_langu.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      LOOP AT lt_tpool INTO DATA(ls_tpool).
        CLEAR ls_out.
        ls_out-id     = ls_tpool-id.
        ls_out-key    = ls_tpool-key.
        ls_out-lang   = lv_langu.
        ls_out-entry  = ls_tpool-entry.
        ls_out-length = ls_tpool-length.
        APPEND ls_out TO lt_out.
      ENDLOOP.

    ENDLOOP.

    IF lt_out IS INITIAL.
      RETURN.
    ENDIF.

    CREATE DATA lr_out LIKE lt_out.
    FIELD-SYMBOLS <lt_ref> TYPE STANDARD TABLE.
    ASSIGN lr_out->* TO <lt_ref>.
    <lt_ref> = lt_out.

    DATA(lo_json) = NEW lcl_json( ).
    lo_json->add_table( iv_table = 'TEXTPOOLT' ir_data = lr_out ).

    add_file( EXPORTING iv_name  = iv_filename
                        it_lines = lo_json->render( )
              CHANGING  ct_files = ct_files ).

  ENDMETHOD.

*----------------------------------------------------------------------*
* Screens
*----------------------------------------------------------------------*
  METHOD dynpro_files.

    " RPY_DYFLOW is itself a table type, not a row type. Declaring
    " STANDARD TABLE OF it built a table of tables, and RPY_DYNPRO_READ
    " hands this straight to RPY_DYNPRO_READ_NATIVE, where the runtime
    " type check of the FLOWLOGIC parameter then failed.
    DATA lt_flow  TYPE TABLE OF rpy_dyflow.
    DATA ls_head  TYPE rpy_dyhead.
    DATA lt_lines TYPE string_table.
    DATA lv_prog  TYPE d020s-prog.

    lv_prog = iv_prog.

    SELECT dnum FROM d020s INTO TABLE @DATA(lt_dynp)
      WHERE prog = @lv_prog
        AND dnum <> '1000'
      ORDER BY dnum.

    LOOP AT lt_dynp INTO DATA(ls_dynp).

      CLEAR: lt_flow, lt_lines.

      CALL FUNCTION 'RPY_DYNPRO_READ'
        EXPORTING
          progname              = lv_prog
          dynnr                 = ls_dynp-dnum
          suppress_exist_checks = 'X'
          suppress_corr_checks  = 'X'
        IMPORTING
          header                = ls_head
        TABLES
          flow_logic            = lt_flow
        EXCEPTIONS
          cancelled             = 1
          not_found             = 2
          permission_error      = 3
          OTHERS                = 4.

      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      FIELD-SYMBOLS <lv_line> TYPE any.
      LOOP AT lt_flow ASSIGNING FIELD-SYMBOL(<ls_flow>).
        " the row is normally a structure wrapping one source line, but
        " fall back to the row itself if the line type is flat, otherwise
        " the flow logic would come out empty without any complaint
        ASSIGN COMPONENT 1 OF STRUCTURE <ls_flow> TO <lv_line>.
        IF sy-subrc <> 0.
          ASSIGN <ls_flow> TO <lv_line>.
        ENDIF.
        IF <lv_line> IS ASSIGNED.
          APPEND |{ <lv_line> }| TO lt_lines.
        ENDIF.
      ENDLOOP.

      add_file( EXPORTING iv_name  = |DYNP { ls_dynp-dnum }.abap|
                          it_lines = lt_lines
                CHANGING  ct_files = ct_files ).

      " screen metadata, keyed by program and screen number
      DATA lt_dtab TYPE STANDARD TABLE OF tabname WITH EMPTY KEY.
      CLEAR lt_dtab.
      APPEND 'D020S' TO lt_dtab.
      APPEND 'D020T' TO lt_dtab.
      APPEND 'D021S' TO lt_dtab.
      APPEND 'D021T' TO lt_dtab.
      APPEND 'D022S' TO lt_dtab.
      APPEND 'D023S' TO lt_dtab.

      DATA(lo_json) = NEW lcl_json( ).

      LOOP AT lt_dtab INTO DATA(lv_dtab).
        DATA lv_where TYPE string.
        DATA(quote_progname) = lcl_meta=>quote( lv_prog ).
        DATA(quote_dnum) = lcl_meta=>quote( ls_dynp-dnum  ).
        CONCATENATE 'PROG = ' quote_progname
                    ' AND DNUM = ' quote_dnum
               INTO lv_where.
        DATA(lr_rows) = lcl_meta=>read_where( iv_table = lv_dtab
                                              iv_where = lv_where ).
        IF lr_rows IS BOUND.
          lo_json->add_table( iv_table = lv_dtab ir_data = lr_rows ).
        ENDIF.
      ENDLOOP.

      IF lo_json->is_empty( ) = abap_false.
        add_file( EXPORTING iv_name  = |DYNP { ls_dynp-dnum }.asx.json|
                            it_lines = lo_json->render( )
                  CHANGING  ct_files = ct_files ).
      ENDIF.

    ENDLOOP.

  ENDMETHOD.

*----------------------------------------------------------------------*
* Function groups
*----------------------------------------------------------------------*
  METHOD split_area.

    DATA lv_area TYPE string.

    CLEAR: ev_ns, ev_short.
    lv_area = iv_area.

    IF strlen( lv_area ) > 1 AND lv_area(1) = '/'.
      FIND REGEX '^(/[^/]+/)(.*)$' IN lv_area
           SUBMATCHES ev_ns ev_short.
      IF sy-subrc <> 0.
        ev_short = lv_area.
      ENDIF.
    ELSE.
      ev_short = lv_area.
    ENDIF.

  ENDMETHOD.

  METHOD fugr_files.

    DATA lv_ns    TYPE string.
    DATA lv_short TYPE string.
    DATA lr_acc   TYPE REF TO data.
    DATA lv_where TYPE string.

    split_area( EXPORTING iv_area  = iv_area
                IMPORTING ev_ns    = lv_ns
                          ev_short = lv_short ).

    DATA lv_main   TYPE program.
    DATA lv_prefix TYPE program.
    DATA lv_pat    TYPE program.

    lv_main   = |{ lv_ns }SAPL{ lv_short }|.
    lv_prefix = |{ lv_ns }L{ lv_short }|.
    lv_pat    = |{ lv_prefix }%|.

    " ---- function modules of the group ---------------------------
    SELECT funcname, include FROM tfdir
      INTO TABLE @DATA(lt_func)
      WHERE pname = @lv_main
      ORDER BY funcname.

    DATA lt_func_incl TYPE HASHED TABLE OF program WITH UNIQUE KEY table_line.

    LOOP AT lt_func INTO DATA(ls_func).

      DATA(lv_uincl) = CONV program( |{ lv_prefix }U{ ls_func-include }| ).
      INSERT lv_uincl INTO TABLE lt_func_incl.

      add_file( EXPORTING iv_name  = |FUNC { encode( ls_func-funcname ) }.abap|
                          it_lines = read_src( lv_uincl )
                CHANGING  ct_files = rt_files ).

      add_file( EXPORTING iv_name  = |FUNC { encode( ls_func-funcname ) }.$.abap|
                          it_lines = func_interface( ls_func-funcname )
                CHANGING  ct_files = rt_files ).

    ENDLOOP.

    " ---- includes of the group, function bodies excluded ---------
    SELECT name FROM trdir
      INTO TABLE @DATA(lt_incl)
      WHERE name LIKE @lv_pat
         OR name = @lv_main
      ORDER BY name.

    LOOP AT lt_incl INTO DATA(ls_incl).

      READ TABLE lt_func_incl WITH TABLE KEY table_line = ls_incl-name
           TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE.                      " already written as a FUNC file
      ENDIF.

      add_file( EXPORTING iv_name  = |REPS { encode( ls_incl-name ) }.abap|
                          it_lines = read_src( ls_incl-name )
                CHANGING  ct_files = rt_files ).

      textpool_file( EXPORTING iv_prog     = ls_incl-name
                               iv_filename = |REPT { encode( ls_incl-name ) }.asx.json|
                     CHANGING  ct_files    = rt_files ).

    ENDLOOP.

    " ---- screens of the group ------------------------------------
    dynpro_files( EXPORTING iv_prog  = lv_main
                  CHANGING  ct_files = rt_files ).

    " ---- group metadata ------------------------------------------
    DATA(lo_json) = NEW lcl_json( ).
    DATA lt_pending TYPE lcl_meta=>tt_pending.
    DATA ls_pending TYPE lcl_meta=>ty_pending.

    " per area
    ls_pending-tabname = 'TLIBG'.
    ls_pending-data    = lcl_meta=>read( iv_table = 'TLIBG' iv_keyfld = 'AREA' iv_value = iv_area ).
    APPEND ls_pending TO lt_pending.
    ls_pending-tabname = 'TLIBT'.
    ls_pending-data    = lcl_meta=>read( iv_table = 'TLIBT' iv_keyfld = 'AREA' iv_value = iv_area ).
    APPEND ls_pending TO lt_pending.

    " per function module
    DATA lt_ftab TYPE STANDARD TABLE OF tabname WITH EMPTY KEY.
    APPEND 'ENLFDIR'   TO lt_ftab.
    APPEND 'FUNCT'     TO lt_ftab.
    APPEND 'FUPARAREF' TO lt_ftab.
    APPEND 'TFDIR'     TO lt_ftab.
    APPEND 'TFTIT'     TO lt_ftab.

    LOOP AT lt_ftab INTO DATA(lv_ftab).
      CLEAR lr_acc.
      LOOP AT lt_func INTO ls_func.
        DATA(lr_one) = lcl_meta=>read( iv_table  = lv_ftab
                                       iv_keyfld = 'FUNCNAME'
                                       iv_value  = ls_func-funcname ).
        collect( EXPORTING ir_source = lr_one
                 CHANGING  cr_target = lr_acc ).
      ENDLOOP.
      ls_pending-tabname = lv_ftab.
      ls_pending-data    = lr_acc.
      APPEND ls_pending TO lt_pending.
    ENDLOOP.

    " per include
    DATA lt_itab TYPE STANDARD TABLE OF tabname WITH EMPTY KEY.
    APPEND 'TRDIR'  TO lt_itab.
    APPEND 'TRDIRT' TO lt_itab.

    LOOP AT lt_itab INTO DATA(lv_itab).
      CLEAR lr_acc.
      LOOP AT lt_incl INTO ls_incl.
        DATA(lr_i) = lcl_meta=>read( iv_table  = lv_itab
                                     iv_keyfld = 'NAME'
                                     iv_value  = ls_incl-name ).
        collect( EXPORTING ir_source = lr_i
                 CHANGING  cr_target = lr_acc ).
      ENDLOOP.
      ls_pending-tabname = lv_itab.
      ls_pending-data    = lr_acc.
      APPEND ls_pending TO lt_pending.
    ENDLOOP.

    " TADIR of the group itself
    ls_pending-tabname = 'TADIR'.
    ls_pending-data    = lcl_meta=>read_tadir( iv_object   = 'FUGR'
                                               iv_obj_name = iv_area ).
    APPEND ls_pending TO lt_pending.

    LOOP AT lt_pending INTO ls_pending.
      ls_pending-sortkey = lcl_meta=>sortkey( ls_pending-tabname ).
      MODIFY lt_pending FROM ls_pending.
    ENDLOOP.
    SORT lt_pending BY sortkey.

    LOOP AT lt_pending INTO ls_pending.
      IF ls_pending-data IS BOUND.
        lo_json->add_table( iv_table = ls_pending-tabname
                            ir_data  = ls_pending-data ).
      ENDIF.
    ENDLOOP.

    IF lo_json->is_empty( ) = abap_false.
      add_file( EXPORTING iv_name  = |FUGR { encode( iv_area ) }.asx.json|
                          it_lines = lo_json->render( )
                CHANGING  ct_files = rt_files ).
    ENDIF.

  ENDMETHOD.

  METHOD func_interface.

    " Rebuilds the generated signature block the function library keeps
    " next to every function module. Reference parameters are prefixed
    " with "!", by value parameters wrapped in VALUE().
    SELECT paramtype, parameter, structure, defaultval, reference, optional
      FROM fupararef
      INTO TABLE @DATA(lt_para)
      WHERE funcname = @iv_func
      ORDER BY paramtype, pposition.

    IF lt_para IS INITIAL.
      RETURN.
    ENDIF.

    APPEND '*******************************************************************' TO rt_lines.
    APPEND '*   THIS FILE IS GENERATED BY THE FUNCTION LIBRARY.               *' TO rt_lines.
    APPEND '*   NEVER CHANGE IT MANUALLY, PLEASE!                             *' TO rt_lines.
    APPEND '*******************************************************************' TO rt_lines.
    APPEND |FUNCTION $$UNIT$$ { iv_func }| TO rt_lines.
    APPEND '' TO rt_lines.

    DATA lv_section TYPE c LENGTH 1.
    DATA lv_line    TYPE string.

    LOOP AT lt_para INTO DATA(ls_para).

      IF ls_para-paramtype <> lv_section.
        lv_section = ls_para-paramtype.
        CASE lv_section.
          WHEN 'I'. APPEND '    IMPORTING'  TO rt_lines.
          WHEN 'E'. APPEND '    EXPORTING'  TO rt_lines.
          WHEN 'C'. APPEND '    CHANGING'   TO rt_lines.
          WHEN 'T'. APPEND '    TABLES'     TO rt_lines.
          WHEN 'X'. APPEND '    EXCEPTIONS' TO rt_lines.
        ENDCASE.
      ENDIF.

      IF lv_section = 'X'.
        APPEND |       !{ ls_para-parameter }| TO rt_lines.
        CONTINUE.
      ENDIF.

      IF ls_para-reference = abap_true OR lv_section = 'T'.
        lv_line = |       !{ ls_para-parameter }|.
      ELSE.
        lv_line = |       VALUE({ ls_para-parameter })|.
      ENDIF.

      IF ls_para-structure IS NOT INITIAL.
        IF lv_section = 'T'.
          lv_line = |{ lv_line } STRUCTURE !{ ls_para-structure }|.
        ELSE.
          lv_line = |{ lv_line } LIKE !{ ls_para-structure }|.
        ENDIF.
      ENDIF.

      IF ls_para-defaultval IS NOT INITIAL.
        lv_line = |{ lv_line } DEFAULT { ls_para-defaultval }|.
      ENDIF.

      APPEND lv_line TO rt_lines.

    ENDLOOP.

    APPEND '         $$GLOBAL.' TO rt_lines.

  ENDMETHOD.

*----------------------------------------------------------------------*
* Documentation objects
*----------------------------------------------------------------------*
  METHOD docu_files.

    DATA lv_id     TYPE dokhl-id.
    DATA lv_doknam TYPE dokhl-object.
    DATA lv_where  TYPE string.

    " DOCV carries the two character documentation id in front of the
    " object name, the other types have a fixed id
    CASE iv_object.
      WHEN 'DOCV'.
        lv_id     = iv_obj_name(2).
        lv_doknam = iv_obj_name+2.
      WHEN 'DOCT'.
        lv_id     = 'TX'.
        lv_doknam = iv_obj_name.
      WHEN 'DSYS'.
        lv_id     = 'HY'.
        lv_doknam = iv_obj_name.
      WHEN OTHERS.
        RETURN.
    ENDCASE.

    SELECT id, object, langu, typ, dokversion FROM dokhl
      INTO TABLE @DATA(lt_dokhl)
      WHERE id     = @lv_id
        AND object = @lv_doknam
      ORDER BY langu, typ, dokversion.

    IF lt_dokhl IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lo_json) = NEW lcl_json( ).

    DATA(quote_id) = lcl_meta=>quote( lv_id ).
    DATA(quote_doknam) = lcl_meta=>quote( lv_doknam ).
    CONCATENATE 'ID = ' quote_id
                ' AND OBJECT = ' quote_doknam
           INTO lv_where.

    DATA(lr_hl) = lcl_meta=>read_where( iv_table = 'DOKHL' iv_where = lv_where ).
    DATA(lr_il) = lcl_meta=>read_where( iv_table = 'DOKIL' iv_where = lv_where ).
    DATA(lr_td) = lcl_meta=>read_tadir( iv_object   = iv_object
                                        iv_obj_name = iv_obj_name ).

    IF lr_hl IS BOUND.
      lo_json->add_table( iv_table = 'DOKHL' ir_data = lr_hl ).
    ENDIF.
    IF lr_il IS BOUND.
      lo_json->add_table( iv_table = 'DOKIL' ir_data = lr_il ).
    ENDIF.
    IF lr_td IS BOUND.
      lo_json->add_table( iv_table = 'TADIR' ir_data = lr_td ).
    ENDIF.

    IF lo_json->is_empty( ) = abap_false.
      add_file( EXPORTING iv_name  = |{ iv_object } { encode( iv_obj_name ) }.asx.json|
                          it_lines = lo_json->render( )
                CHANGING  ct_files = rt_files ).
    ENDIF.

    " one text file per language and version, the name is the DOKHL key
    LOOP AT lt_dokhl INTO DATA(ls_dokhl).

      DATA lt_text TYPE STANDARD TABLE OF tline WITH EMPTY KEY.
      DATA ls_head TYPE thead.
      CLEAR: lt_text, ls_head.

      CALL FUNCTION 'DOCU_GET'
        EXPORTING
          id      = ls_dokhl-id
          langu   = ls_dokhl-langu
          object  = ls_dokhl-object
          typ     = ls_dokhl-typ
          version = ls_dokhl-dokversion
        IMPORTING
          head    = ls_head
        TABLES
          line    = lt_text
        EXCEPTIONS
          OTHERS  = 1.

      IF sy-subrc <> 0 OR lt_text IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA lt_lines TYPE string_table.
      CLEAR lt_lines.
      LOOP AT lt_text INTO DATA(ls_text).
        APPEND |{ ls_text-tdformat }{ ls_text-tdline }| TO lt_lines.
      ENDLOOP.

      DATA(lv_fname) = |DOCU { ls_dokhl-id } { ls_dokhl-object WIDTH = 60 } | &&
                       |{ ls_dokhl-langu } { ls_dokhl-typ } | &&
                       |{ ls_dokhl-dokversion WIDTH = 4 PAD = '0' ALIGN = RIGHT }.txt|.

      add_file( EXPORTING iv_name  = lv_fname
                          it_lines = lt_lines
                CHANGING  ct_files = rt_files ).

    ENDLOOP.

  ENDMETHOD.

  METHOD composed_files.

    CASE iv_object.
      WHEN 'FUGR'.
        rt_files = fugr_files( iv_obj_name ).
      WHEN 'DOCT' OR 'DOCV' OR 'DSYS'.
        rt_files = docu_files( iv_object   = iv_object
                               iv_obj_name = iv_obj_name ).
      WHEN OTHERS.
        RETURN.
    ENDCASE.

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& LCL_TRANSPORT - the objects of a transport request
*&
*& A request carries its objects in E071, but almost always on its tasks
*& rather than on the request header, and mostly as LIMU sub-objects: a
*& changed method arrives as LIMU METH, not as R3TR CLAS. Everything has
*& to be lifted to its R3TR owner before it can be exported, because the
*& repository stores whole objects.
*&
*& Anything that cannot be lifted is reported rather than dropped, so a
*& request never looks fully exported when part of it was not understood.
*&---------------------------------------------------------------------*
CLASS lcl_transport DEFINITION CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS objects
      IMPORTING iv_trkorr     TYPE trkorr
      EXPORTING et_obj        TYPE tt_obj
                et_unresolved TYPE tt_log.

  PRIVATE SECTION.
    CLASS-METHODS resolve
      IMPORTING iv_pgmid  TYPE pgmid
                iv_object TYPE trobjtype
                iv_name   TYPE sobj_name
      EXPORTING ev_object TYPE trobjtype
                ev_name   TYPE sobj_name.

    "! Owner of a generated class or interface include. The owner sits in
    "! the first 30 characters, blank padded by E071 or "=" padded by the
    "! include generator.
    CLASS-METHODS clif_name
      IMPORTING iv_raw         TYPE clike
      RETURNING VALUE(rv_name) TYPE sobj_name.

    "! /NS/SAPLFOO -> /NS/FOO, SAPLZFOO -> ZFOO
    CLASS-METHODS area_of
      IMPORTING iv_pname       TYPE clike
      RETURNING VALUE(rv_area) TYPE sobj_name.

ENDCLASS.

CLASS lcl_transport IMPLEMENTATION.

  METHOD clif_name.

    DATA lv_raw TYPE c LENGTH 30.

    lv_raw = iv_raw.
    TRANSLATE lv_raw USING '= '.
    rv_name = lv_raw.

  ENDMETHOD.

  METHOD area_of.

    DATA lv_p     TYPE string.
    DATA lv_ns    TYPE string.
    DATA lv_short TYPE string.

    lv_p = iv_pname.

    FIND REGEX '^(/[^/]+/)?SAPL(.+)$' IN lv_p
         SUBMATCHES lv_ns lv_short.
    IF sy-subrc = 0.
      rv_area = |{ lv_ns }{ lv_short }|.
    ENDIF.

  ENDMETHOD.

  METHOD resolve.

    CLEAR: ev_object, ev_name.

    IF iv_pgmid = 'R3TR'.
      ev_object = iv_object.
      ev_name   = iv_name.
      RETURN.
    ENDIF.

    IF iv_pgmid <> 'LIMU'.
      RETURN.
    ENDIF.

    CASE iv_object.

        " every class part names its class in the first 30 characters
      WHEN 'CLSD' OR 'CPUB' OR 'CPRO' OR 'CPRI' OR 'CINC' OR 'METH'
        OR 'CLSC' OR 'CDEF' OR 'CIMP' OR 'CMAC' OR 'CAUS' OR 'CLLI'
        OR 'CPRV' OR 'CDER'.
        ev_object = 'CLAS'.
        ev_name   = clif_name( iv_name ).

      WHEN 'INTD' OR 'INTC'.
        ev_object = 'INTF'.
        ev_name   = clif_name( iv_name ).

      WHEN 'FUNC'.
        SELECT SINGLE pname FROM tfdir INTO @DATA(lv_pname)
          WHERE funcname = @iv_name.
        IF sy-subrc = 0.
          ev_name = area_of( lv_pname ).
          IF ev_name IS NOT INITIAL.
            ev_object = 'FUGR'.
          ENDIF.
        ENDIF.

      WHEN 'REPS' OR 'REPT' OR 'DYNP' OR 'CUAD' OR 'DOCU'.
        " a report source is either a program in its own right or an
        " include of a function group; D010INC knows the master program
        SELECT SINGLE obj_name FROM tadir INTO @DATA(lv_prog)
          WHERE pgmid    = 'R3TR'
            AND object   = 'PROG'
            AND obj_name = @iv_name.
        IF sy-subrc = 0.
          ev_object = 'PROG'.
          ev_name   = lv_prog.
          RETURN.
        ENDIF.

        SELECT SINGLE master FROM d010inc INTO @DATA(lv_master)
          WHERE include = @iv_name.
        IF sy-subrc = 0 AND lv_master CS 'SAPL'.
          ev_name = area_of( lv_master ).
          IF ev_name IS NOT INITIAL.
            ev_object = 'FUGR'.
          ENDIF.
        ENDIF.

      WHEN 'TABD' OR 'TABT' OR 'INDX' OR 'SQLT'.
        ev_object = 'TABL'.
        ev_name   = clif_name( iv_name ).

      WHEN 'DOMD'.
        ev_object = 'DOMA'.
        ev_name   = iv_name.

      WHEN 'DTED'.
        ev_object = 'DTEL'.
        ev_name   = iv_name.

      WHEN 'VIED'.
        ev_object = 'VIEW'.
        ev_name   = iv_name.

      WHEN 'SHLD'.
        ev_object = 'SHLP'.
        ev_name   = iv_name.

      WHEN 'ENQD'.
        ev_object = 'ENQU'.
        ev_name   = iv_name.

      WHEN 'TTYD'.
        ev_object = 'TTYP'.
        ev_name   = iv_name.

      WHEN 'MESS'.
        " ARBGB(20) followed by the message number
        ev_object = 'MSAG'.
        DATA lv_arbgb TYPE c LENGTH 20.
        lv_arbgb = iv_name.
        ev_name  = lv_arbgb.

      WHEN OTHERS.
        " left unresolved on purpose, the caller logs it
    ENDCASE.

  ENDMETHOD.

  METHOD objects.

    DATA lt_req   TYPE STANDARD TABLE OF trkorr WITH EMPTY KEY.
    DATA ls_obj   TYPE ty_obj.
    DATA ls_log   TYPE ty_log.
    DATA lv_objct TYPE trobjtype.
    DATA lv_name  TYPE sobj_name.

    CLEAR: et_obj, et_unresolved.

    " the request itself and every task below it
    SELECT trkorr FROM e070
      INTO TABLE @lt_req
      WHERE trkorr  = @iv_trkorr
         OR strkorr = @iv_trkorr.

    IF lt_req IS INITIAL.
      RETURN.
    ENDIF.

    SELECT pgmid, object, obj_name FROM e071
      FOR ALL ENTRIES IN @lt_req
      WHERE trkorr = @lt_req-table_line
      INTO TABLE @DATA(lt_e071).

    LOOP AT lt_e071 INTO DATA(ls_e071).

      resolve( EXPORTING iv_pgmid  = ls_e071-pgmid
                         iv_object = ls_e071-object
                         iv_name   = CONV #( ls_e071-obj_name )
               IMPORTING ev_object = lv_objct
                         ev_name   = lv_name ).

      CLEAR ls_log.
      ls_log-object   = ls_e071-object.
      ls_log-obj_name = ls_e071-obj_name.

      IF lv_objct IS INITIAL.
        ls_log-status  = 'UNRESOLVED'.
        ls_log-message = |{ ls_e071-pgmid } { ls_e071-object } has no R3TR mapping|.
        APPEND ls_log TO et_unresolved.
        CONTINUE.
      ENDIF.

      " an object can only be placed if the repository knows its package
      SELECT SINGLE devclass FROM tadir INTO @DATA(lv_devc)
        WHERE pgmid    = 'R3TR'
          AND object   = @lv_objct
          AND obj_name = @lv_name.

      IF sy-subrc <> 0.
        ls_log-status  = 'NO TADIR'.
        ls_log-message = |Resolved to { lv_objct } { lv_name }, which has no TADIR entry|.
        APPEND ls_log TO et_unresolved.
        CONTINUE.
      ENDIF.

      CLEAR ls_obj.
      ls_obj-object   = lv_objct.
      ls_obj-obj_name = lv_name.
      ls_obj-devclass = lv_devc.
      APPEND ls_obj TO et_obj.

    ENDLOOP.

    " many LIMU rows collapse onto the same owner
    SORT et_obj BY object obj_name.
    DELETE ADJACENT DUPLICATES FROM et_obj COMPARING object obj_name.

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& LCL_EXPORTER - walks the package and lays out the repository
*&---------------------------------------------------------------------*
CLASS lcl_exporter DEFINITION CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING iv_root   TYPE string
                iv_devc   TYPE devclass
                iv_sub    TYPE abap_bool
                iv_meta   TYPE abap_bool
                iv_src    TYPE abap_bool
                iv_dry    TYPE abap_bool
                iv_trkorr TYPE trkorr OPTIONAL.

    METHODS run.

    METHODS log
      RETURNING VALUE(rt_log) TYPE tt_log.

    METHODS file_count
      RETURNING VALUE(rv_count) TYPE i.

    METHODS error_count
      RETURNING VALUE(rv_count) TYPE i.

    "! Path of the archive that was written, filled by RUN
    METHODS archive
      RETURNING VALUE(rv_file) TYPE string.

  PRIVATE SECTION.
    "! Repository-relative folder of a package, "" for the export package
    TYPES:
      BEGIN OF ty_pkgpath,
        devclass TYPE devclass,
        path     TYPE string,
      END OF ty_pkgpath.

    DATA mv_devc    TYPE devclass.
    DATA mv_sub     TYPE abap_bool.
    DATA mv_meta    TYPE abap_bool.
    DATA mv_src     TYPE abap_bool.
    DATA mv_trkorr  TYPE trkorr.
    DATA mo_fs      TYPE REF TO lcl_fs.
    DATA mt_log     TYPE tt_log.
    DATA mv_archive TYPE string.
    DATA mt_pkgpath TYPE HASHED TABLE OF ty_pkgpath WITH UNIQUE KEY devclass.

    "! Folder of a package relative to the repository root, resolved on
    "! demand because a request may touch packages the walk never saw.
    METHODS pkgpath_for
      IMPORTING iv_devclass    TYPE devclass
      RETURNING VALUE(rv_path) TYPE string.

    METHODS packages
      RETURNING VALUE(rt_devc) TYPE tt_devc.

    METHODS collect_objects
      RETURNING VALUE(rt_obj) TYPE tt_obj.

    METHODS write_root.

    "! Written on every export. Its timestamp changes each run, which is
    "! what makes a push always land as a commit, so a transport request
    "! is always visible as its own version in the repository history.
    METHODS write_manifest
      IMPORTING it_obj TYPE tt_obj.

    METHODS export_object
      IMPORTING is_obj TYPE ty_obj.

    METHODS metadata_file
      IMPORTING is_obj    TYPE ty_obj
      EXPORTING et_lines  TYPE string_table
                ev_tables TYPE i.

ENDCLASS.

CLASS lcl_exporter IMPLEMENTATION.

  METHOD constructor.

    mv_devc   = iv_devc.
    mv_sub    = iv_sub.
    mv_meta   = iv_meta.
    mv_src    = iv_src.
    mv_trkorr = iv_trkorr.

    " /NS/PACKAGE cannot be a file name, so the namespace slashes go.
    " A request exports under its own number, which keeps successive
    " delta archives apart in the download folder.
    DATA lv_zipname TYPE string.
    IF mv_trkorr IS NOT INITIAL.
      lv_zipname = mv_trkorr.
    ELSE.
      lv_zipname = iv_devc.
    ENDIF.
    REPLACE ALL OCCURRENCES OF '/' IN lv_zipname WITH '_'.
    SHIFT lv_zipname LEFT DELETING LEADING '_'.
    IF lv_zipname IS INITIAL.
      lv_zipname = 'export'.
    ENDIF.

    mo_fs = NEW lcl_fs( iv_root    = iv_root
                        iv_zipname = lv_zipname
                        iv_dry     = iv_dry ).

  ENDMETHOD.

  METHOD log.
    rt_log = mt_log.
  ENDMETHOD.

  METHOD archive.
    rv_file = mv_archive.
  ENDMETHOD.

  METHOD file_count.
    rv_count = mo_fs->file_count( ).
  ENDMETHOD.

  METHOD packages.

    DATA lt_todo TYPE tt_devc.
    DATA ls_path TYPE ty_pkgpath.
    DATA lv_par  TYPE string.

    " a request export with no anchor has nothing to walk, and walking
    " from a blank package would collect every top level package there is
    IF mv_devc IS INITIAL.
      RETURN.
    ENDIF.

    APPEND mv_devc TO rt_devc.

    " the export package is the repository root, so it gets no folder of
    " its own, exactly as abapGit puts the root package straight in src/
    CLEAR ls_path.
    ls_path-devclass = mv_devc.
    INSERT ls_path INTO TABLE mt_pkgpath.

    IF mv_sub = abap_false.
      RETURN.
    ENDIF.

    lt_todo = rt_devc.

    WHILE lt_todo IS NOT INITIAL.

      SELECT devclass, parentcl
        FROM tdevc
        FOR ALL ENTRIES IN @lt_todo
        WHERE parentcl = @lt_todo-table_line
        INTO TABLE @DATA(lt_child).

      CLEAR lt_todo.

      LOOP AT lt_child INTO DATA(ls_child).

        READ TABLE rt_devc WITH KEY table_line = ls_child-devclass
             TRANSPORTING NO FIELDS.
        IF sy-subrc = 0.
          CONTINUE.
        ENDIF.

        APPEND ls_child-devclass TO rt_devc.
        APPEND ls_child-devclass TO lt_todo.

        " abapGit names a subpackage folder after the full package name,
        " lower case with "/" replaced by "#", and nests it below its
        " parent: #ns#api/#ns#api_outbound
        DATA(lv_folder) = to_lower( ls_child-devclass ).
        REPLACE ALL OCCURRENCES OF '/' IN lv_folder WITH '#'.

        CLEAR lv_par.
        READ TABLE mt_pkgpath INTO DATA(ls_par)
             WITH TABLE KEY devclass = ls_child-parentcl.
        IF sy-subrc = 0.
          lv_par = ls_par-path.
        ENDIF.

        CLEAR ls_path.
        ls_path-devclass = ls_child-devclass.
        IF lv_par IS INITIAL.
          ls_path-path = lv_folder.
        ELSE.
          ls_path-path = |{ lv_par }/{ lv_folder }|.
        ENDIF.
        INSERT ls_path INTO TABLE mt_pkgpath.

      ENDLOOP.

    ENDWHILE.

    SORT rt_devc.

  ENDMETHOD.

  METHOD collect_objects.

    " the package walk runs either way: it seeds MT_PKGPATH so the folder
    " layout of a request delta matches a full export of the same package
    DATA(lt_devc) = packages( ).

    IF mv_trkorr IS NOT INITIAL.

      lcl_transport=>objects( EXPORTING iv_trkorr     = mv_trkorr
                              IMPORTING et_obj        = rt_obj
                                        et_unresolved = DATA(lt_unresolved) ).

      " unresolved rows go straight into the result list, so a request is
      " never reported as fully exported when part of it was skipped
      APPEND LINES OF lt_unresolved TO mt_log.
      RETURN.

    ENDIF.

    SELECT object, obj_name, devclass
      FROM tadir
      FOR ALL ENTRIES IN @lt_devc
      WHERE pgmid    = 'R3TR'
        AND devclass = @lt_devc-table_line
        AND delflag  = @space
      INTO CORRESPONDING FIELDS OF TABLE @rt_obj.

    SORT rt_obj BY object obj_name.

  ENDMETHOD.

  METHOD pkgpath_for.

    DATA lt_chain TYPE STANDARD TABLE OF devclass WITH EMPTY KEY.
    DATA lv_cur   TYPE devclass.
    DATA lv_par   TYPE devclass.
    DATA ls_path  TYPE ty_pkgpath.

    READ TABLE mt_pkgpath INTO DATA(ls_hit)
         WITH TABLE KEY devclass = iv_devclass.
    IF sy-subrc = 0.
      rv_path = ls_hit-path.
      RETURN.
    ENDIF.

    " climb to the repository root, collecting the chain on the way. The
    " counter caps a cycle in TDEVC rather than trusting the data.
    lv_cur = iv_devclass.
    DO 30 TIMES.
      IF lv_cur IS INITIAL OR lv_cur = mv_devc.
        EXIT.
      ENDIF.
      INSERT lv_cur INTO lt_chain INDEX 1.
      SELECT SINGLE parentcl FROM tdevc INTO @lv_par
        WHERE devclass = @lv_cur.
      IF sy-subrc <> 0.
        CLEAR lv_par.
      ENDIF.
      lv_cur = lv_par.
    ENDDO.

    LOOP AT lt_chain INTO DATA(lv_seg).
      DATA(lv_folder) = to_lower( lv_seg ).
      REPLACE ALL OCCURRENCES OF '/' IN lv_folder WITH '#'.
      IF rv_path IS INITIAL.
        rv_path = lv_folder.
      ELSE.
        rv_path = |{ rv_path }/{ lv_folder }|.
      ENDIF.
    ENDLOOP.

    ls_path-devclass = iv_devclass.
    ls_path-path     = rv_path.
    INSERT ls_path INTO TABLE mt_pkgpath.

  ENDMETHOD.

  METHOD error_count.
    rv_count = mo_fs->error_count( ).
  ENDMETHOD.

  METHOD write_root.

    DATA lt_lines TYPE string_table.
    DATA lv_name  TYPE string.
    DATA lv_desc  TYPE string.

    lv_name = p_name.
    lv_desc = p_desc.

    IF lv_name IS INITIAL.
      lv_name = to_lower( mv_devc ).
      REPLACE ALL OCCURRENCES OF '/' IN lv_name WITH ''.
      REPLACE ALL OCCURRENCES OF '_' IN lv_name WITH '-'.
    ENDIF.
    IF lv_desc IS INITIAL.
      SELECT SINGLE ctext FROM tdevct INTO @lv_desc
        WHERE devclass = @mv_devc AND spras = @sy-langu.
      IF lv_desc IS INITIAL.
        lv_desc = mv_devc.
      ENDIF.
    ENDIF.

    " .gcts.properties.json, two space indent as gCTS writes it
    APPEND '{'                                        TO lt_lines.
    APPEND |  "name": "{ lcl_json=>escape( lv_name ) }",| TO lt_lines.
    APPEND '  "version": "1.0.0",'                    TO lt_lines.
    APPEND |  "description": "{ lcl_json=>escape( lv_desc ) }",| TO lt_lines.
    APPEND '  "repositoryLayout": {'                  TO lt_lines.
    APPEND '    "format": "json",'                    TO lt_lines.
    APPEND '    "formatVersion": "6",'                TO lt_lines.
    APPEND '    "keepClient": "false",'               TO lt_lines.
    APPEND '    "metaInformation": ".gctsmetadata/",' TO lt_lines.
    APPEND '    "tableContent": "true"'               TO lt_lines.
    APPEND '  }'                                      TO lt_lines.
    APPEND '}'                                        TO lt_lines.

    mo_fs->write_text( iv_rel = '.gcts.properties.json' it_lines = lt_lines ).

    CLEAR lt_lines.
    APPEND |# { mv_devc }| TO lt_lines.
    APPEND ''              TO lt_lines.
    APPEND |{ lv_desc }|   TO lt_lines.
    APPEND ''              TO lt_lines.
    APPEND 'gCTS shaped export produced by report ZGCTS_EXPORT from'  TO lt_lines.
    APPEND |system { sy-sysid } client { sy-mandt } on { sy-datum DATE = ISO }.| TO lt_lines.
    APPEND ''                                                          TO lt_lines.
    APPEND '## Layout'                                                 TO lt_lines.
    APPEND ''                                                          TO lt_lines.
    APPEND '    objects/<PKGPATH>/<OBJTYPE>/<OBJNAME>/<OBJTYPE> <NAME>.asx.json  table rows' TO lt_lines.
    APPEND '    objects/<PKGPATH>/<OBJTYPE>/<OBJNAME>/<PART> <NAME>.abap         source parts' TO lt_lines.
    APPEND ''                                                          TO lt_lines.
    APPEND 'PKGPATH follows the package hierarchy, named the way abapGit' TO lt_lines.
    APPEND 'names it: full package name, lower case, "/" as "#". Objects' TO lt_lines.
    APPEND 'of the exported package itself sit directly under objects/.'  TO lt_lines.
    APPEND 'Example: objects/#ns#api/#ns#api_outbound/CLAS/...'         TO lt_lines.
    APPEND ''                                                          TO lt_lines.
    APPEND '## Known differences from a native gCTS repository'        TO lt_lines.
    APPEND ''                                                          TO lt_lines.
    APPEND '- Metadata is read from the dictionary and repository tables'  TO lt_lines.
    APPEND '  rather than written by R3trans, so DDIC version fields carry' TO lt_lines.
    APPEND '  the active value A instead of the transport internal L or N.' TO lt_lines.
    APPEND '- .gctsmetadata/nametabs is not generated.'                TO lt_lines.
    APPEND '- Namespaced names are URL encoded, / as %2F, like gCTS'   TO lt_lines.
    APPEND '  already encodes ~ as %7E in method file names.'          TO lt_lines.
    APPEND '- Text pools are exported in the master and logon language.' TO lt_lines.
    APPEND '- The export is meant to be read, reviewed and diffed. It is' TO lt_lines.
    APPEND '  not guaranteed to be importable by gCTS.'                TO lt_lines.

    mo_fs->write_text( iv_rel = 'README.md' it_lines = lt_lines ).

  ENDMETHOD.

  METHOD write_manifest.

    DATA lt_lines TYPE string_table.
    DATA lv_user  TYPE e070-as4user.
    DATA lv_date  TYPE e070-as4date.
    DATA lv_text  TYPE e07t-as4text.

    DATA(root_package_name) = lcl_json=>escape( CONV string( mv_devc ) ).
    APPEND '{'                                                     TO lt_lines.
    APPEND |  "exportedAt": "{ sy-datum DATE = ISO }T{ sy-uzeit TIME = ISO }",| TO lt_lines.
    APPEND |  "system": "{ sy-sysid }",|                           TO lt_lines.
    APPEND |  "client": "{ sy-mandt }",|                           TO lt_lines.
    APPEND |  "exportedBy": "{ sy-uname }",|                       TO lt_lines.
    APPEND |  "rootPackage": "{ root_package_name }",|    TO lt_lines.

    IF mv_trkorr IS INITIAL.

      APPEND '  "source": "package",'                              TO lt_lines.
      APPEND |  "objects": { lines( it_obj ) }|                    TO lt_lines.

    ELSE.

      APPEND '  "source": "transport",'                            TO lt_lines.

      SELECT SINGLE as4user, as4date FROM e070
        INTO (@lv_user, @lv_date)
        WHERE trkorr = @mv_trkorr.

      " the short text is language dependent, fall back to any language
      SELECT SINGLE as4text FROM e07t INTO @lv_text
        WHERE trkorr = @mv_trkorr AND langu = @sy-langu.
      IF sy-subrc <> 0.
        SELECT SINGLE as4text FROM e07t INTO @lv_text
          WHERE trkorr = @mv_trkorr.
      ENDIF.

      DATA(description) = lcl_json=>escape( CONV string( lv_text ) ).
      APPEND '  "transport": {'                                    TO lt_lines.
      APPEND |    "id": "{ mv_trkorr }",|                          TO lt_lines.
      APPEND |    "description": "{ description }",| TO lt_lines.
      APPEND |    "owner": "{ lv_user }",|                         TO lt_lines.
      APPEND |    "date": "{ lv_date DATE = ISO }"|                TO lt_lines.
      APPEND '  },'                                                TO lt_lines.
      APPEND |  "objects": { lines( it_obj ) },|                   TO lt_lines.

      " a delta is small enough to list, a whole package is not
      APPEND '  "objectList": ['                                   TO lt_lines.
      DATA(lv_last) = lines( it_obj ).

      LOOP AT it_obj INTO DATA(ls_obj).
        DATA(objectname) = lcl_json=>escape( CONV string( ls_obj-obj_name ) ).
        IF sy-tabix < lv_last.
          APPEND |    "{ ls_obj-object } { objectname }",| TO lt_lines.
        ELSE.
          APPEND |    "{ ls_obj-object } { objectname }"|  TO lt_lines.
        ENDIF.
      ENDLOOP.
      APPEND '  ]'                                                 TO lt_lines.

    ENDIF.

    APPEND '}'                                                     TO lt_lines.

    mo_fs->write_text( iv_rel   = '.zgcts/export.json'
                       it_lines = lt_lines ).

  ENDMETHOD.

  METHOD metadata_file.

    DATA lt_pending TYPE lcl_meta=>tt_pending.
    DATA ls_pending TYPE lcl_meta=>ty_pending.
    DATA lr_acc     TYPE REF TO data.

    CLEAR: et_lines, ev_tables.

    DATA(lt_map) = lcl_meta=>tables_for( is_obj-object ).

    LOOP AT lt_map INTO DATA(ls_map).
      CLEAR ls_pending.
      ls_pending-tabname = ls_map-tabname.
      ls_pending-sortkey = lcl_meta=>sortkey( ls_map-tabname ).
      ls_pending-data    = lcl_meta=>read( iv_table  = ls_map-tabname
                                           iv_keyfld = ls_map-keyfld
                                           iv_value  = is_obj-obj_name ).
      IF ls_pending-data IS BOUND.
        APPEND ls_pending TO lt_pending.
      ENDIF.
    ENDLOOP.

    " classes and interfaces additionally carry the TRDIR row of their pool
    IF is_obj-object = 'CLAS' OR is_obj-object = 'INTF'.
      DATA lv_pool TYPE program.
      IF is_obj-object = 'CLAS'.
        lv_pool = cl_oo_classname_service=>get_classpool_name( CONV seoclsname( is_obj-obj_name ) ).
      ELSE.
        lv_pool = cl_oo_classname_service=>get_interfacepool_name( CONV seoclsname( is_obj-obj_name ) ).
      ENDIF.
      CLEAR ls_pending.
      ls_pending-tabname = 'TRDIR'.
      ls_pending-sortkey = lcl_meta=>sortkey( 'TRDIR' ).
      ls_pending-data    = lcl_meta=>read( iv_table  = 'TRDIR'
                                           iv_keyfld = 'NAME'
                                           iv_value  = lv_pool ).
      IF ls_pending-data IS BOUND.
        APPEND ls_pending TO lt_pending.
      ENDIF.
    ENDIF.

    " TADIR takes its normal place in the alphabetical order
    CLEAR ls_pending.
    ls_pending-tabname = 'TADIR'.
    ls_pending-sortkey = lcl_meta=>sortkey( 'TADIR' ).
    ls_pending-data    = lcl_meta=>read_tadir( iv_object   = is_obj-object
                                               iv_obj_name = is_obj-obj_name ).
    IF ls_pending-data IS BOUND.
      APPEND ls_pending TO lt_pending.
    ENDIF.

    SORT lt_pending BY sortkey.

    DATA(lo_json) = NEW lcl_json( ).

    LOOP AT lt_pending INTO ls_pending.
      lo_json->add_table( iv_table = ls_pending-tabname
                          ir_data  = ls_pending-data ).
    ENDLOOP.

    ev_tables = lines( lt_pending ).
    et_lines  = lo_json->render( ).

  ENDMETHOD.

  METHOD export_object.

    DATA ls_log   TYPE ty_log.
    DATA lt_files TYPE tt_file.
    DATA lt_meta  TYPE string_table.
    DATA lv_tabs  TYPE i.

    ls_log-object   = is_obj-object.
    ls_log-obj_name = is_obj-obj_name.
    ls_log-status   = 'OK'.

    " objects live under their own package, the way abapGit lays them out,
    " with the gCTS <TYPE>/<NAME>/ pair below that
    DATA(lv_pkg) = pkgpath_for( is_obj-devclass ).

    DATA lv_folder TYPE string.

    IF lv_pkg IS INITIAL.
      lv_folder = |objects/{ is_obj-object }/{ lcl_src=>encode( is_obj-obj_name ) }|.
    ELSE.
      lv_folder = |objects/{ lv_pkg }/{ is_obj-object }/{ lcl_src=>encode( is_obj-obj_name ) }|.
    ENDIF.

    IF lcl_src=>handles( is_obj-object ) = abap_true.

      " self contained types deliver metadata and source in one go
      lt_files = lcl_src=>composed_files( iv_object   = is_obj-object
                                          iv_obj_name = is_obj-obj_name ).
      ls_log-tables = 0.

    ELSE.

      IF mv_meta = abap_true.
        metadata_file( EXPORTING is_obj    = is_obj
                       IMPORTING et_lines  = lt_meta
                                 ev_tables = lv_tabs ).
        ls_log-tables = lv_tabs.

        IF lt_meta IS NOT INITIAL.
          APPEND VALUE ty_file(
            name  = |{ is_obj-object } { lcl_src=>encode( is_obj-obj_name ) }.asx.json|
            lines = lt_meta ) TO lt_files.
        ENDIF.
      ENDIF.

      IF mv_src = abap_true.
        APPEND LINES OF lcl_src=>source_files( iv_object   = is_obj-object
                                               iv_obj_name = is_obj-obj_name ) TO lt_files.
      ENDIF.

      IF lcl_meta=>tables_for( is_obj-object ) IS INITIAL.
        ls_log-status  = 'TADIR ONLY'.
        ls_log-message = |Composition of { is_obj-object } is not declared in LCL_META|.
      ENDIF.

    ENDIF.

    IF lt_files IS INITIAL.
      ls_log-status  = 'SKIPPED'.
      ls_log-message = 'Nothing readable found for this object'.
      APPEND ls_log TO mt_log.
      RETURN.
    ENDIF.

    mo_fs->mkdir( lv_folder ).

    LOOP AT lt_files INTO DATA(ls_file).
      mo_fs->write_text( iv_rel   = |{ lv_folder }/{ ls_file-name }|
                         it_lines = ls_file-lines ).
    ENDLOOP.

    ls_log-files = lines( lt_files ).
    APPEND ls_log TO mt_log.

  ENDMETHOD.

  METHOD run.

    DATA(lt_obj) = collect_objects( ).

    IF lt_obj IS INITIAL.
      IF mv_trkorr IS INITIAL.
        MESSAGE |Package { mv_devc } holds no transportable objects| TYPE 'S'
                DISPLAY LIKE 'W'.
      ELSE.
        " MT_LOG may still carry unresolved rows worth showing
        MESSAGE |Request { mv_trkorr } yielded no exportable objects| TYPE 'S'
                DISPLAY LIKE 'W'.
      ENDIF.
      RETURN.
    ENDIF.

    " a request delta lands in a repository that already has its root
    " files, and rewriting them would put churn in every commit
    IF mv_trkorr IS INITIAL.
      write_root( ).
    ENDIF.

    write_manifest( lt_obj ).

    DATA(lv_total) = lines( lt_obj ).
    DATA lv_pct TYPE i.

    " TEXT of SAPGUI_PROGRESS_INDICATOR is a generic TYPE C parameter and
    " function module parameters are type checked at runtime, so handing
    " it a string template raises CX_SY_DYN_CALL_ILLEGAL_TYPE. The value
    " has to travel in a fixed length character field.
    DATA lv_ptext TYPE c LENGTH 100.

    LOOP AT lt_obj INTO DATA(ls_obj).

      IF sy-tabix MOD 20 = 0 OR sy-tabix = 1.
        lv_pct   = sy-tabix * 100 / lv_total.
        lv_ptext = |{ sy-tabix }/{ lv_total } { ls_obj-object } { ls_obj-obj_name }|.
        CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
          EXPORTING
            percentage = lv_pct
            text       = lv_ptext.
      ENDIF.

      export_object( ls_obj ).

    ENDLOOP.

    lv_ptext = 'Building archive and sending it to the frontend'.
    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING
        percentage = 100
        text       = lv_ptext.

    mv_archive = mo_fs->finalize( ).

  ENDMETHOD.

ENDCLASS.

*&---------------------------------------------------------------------*
*& Screen behaviour
*&---------------------------------------------------------------------*
INITIALIZATION.
  gv_t01 = 'Source package'.
  gv_t02 = 'Target repository'.
  gv_t03 = 'Options'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_path.
  DATA lv_folder TYPE string.
  cl_gui_frontend_services=>directory_browse(
    EXPORTING  window_title    = 'Repository root folder'
    CHANGING   selected_folder = lv_folder
    EXCEPTIONS OTHERS          = 1 ).
  IF sy-subrc = 0 AND lv_folder IS NOT INITIAL.
    p_path = lv_folder.
  ENDIF.

AT SELECTION-SCREEN.

  " a package export cannot proceed without its package
  IF p_bypkg = abap_true AND p_devc IS INITIAL.
    MESSAGE 'Enter the package to export' TYPE 'E'.
  ENDIF.

  " a request export may leave it blank, but a value given must be real
  IF p_devc IS NOT INITIAL.
    SELECT SINGLE devclass FROM tdevc INTO @DATA(lv_check)
      WHERE devclass = @p_devc.
    IF sy-subrc <> 0.
      MESSAGE |Package { p_devc } does not exist| TYPE 'E'.
    ENDIF.
  ENDIF.

  IF p_bytr = abap_true.
    IF p_trkorr IS INITIAL.
      MESSAGE 'Enter the transport request to export' TYPE 'E'.
    ENDIF.
    SELECT SINGLE trkorr FROM e070 INTO @DATA(lv_tr)
      WHERE trkorr = @p_trkorr.
    IF sy-subrc <> 0.
      MESSAGE |Transport request { p_trkorr } does not exist| TYPE 'E'.
    ENDIF.
  ENDIF.

*&---------------------------------------------------------------------*
*& Main
*&---------------------------------------------------------------------*
START-OF-SELECTION.

  DATA gv_trkorr TYPE trkorr.
  IF p_bytr = abap_true.
    gv_trkorr = p_trkorr.
  ENDIF.

  DATA(go_export) = NEW lcl_exporter( iv_root   = p_path
                                      iv_devc   = p_devc
                                      iv_sub    = p_sub
                                      iv_meta   = p_meta
                                      iv_src    = p_src
                                      iv_dry    = p_dry
                                      iv_trkorr = gv_trkorr ).

  TRY.
      go_export->run( ).
    CATCH cx_root INTO DATA(gx_err).
      DATA(gv_msg) = gx_err->get_text( ).
      MESSAGE gv_msg TYPE 'E' DISPLAY LIKE 'E'.
  ENDTRY.

END-OF-SELECTION.

  DATA(gt_log) = go_export->log( ).

  IF gt_log IS INITIAL.
    RETURN.
  ENDIF.

  DATA gv_ok      TYPE i.
  DATA gv_partial TYPE i.
  DATA gv_skipped TYPE i.

  LOOP AT gt_log INTO DATA(gs_log).
    CASE gs_log-status.
      WHEN 'OK'.         gv_ok      = gv_ok + 1.
      WHEN 'TADIR ONLY'. gv_partial = gv_partial + 1.
      WHEN OTHERS.       gv_skipped = gv_skipped + 1.
    ENDCASE.
  ENDLOOP.

  IF p_dry = abap_true.
    WRITE: / 'SIMULATION - nothing was written to the frontend'.
    SKIP.
  ENDIF.

  DATA(gv_objects) = lines( gt_log ).
  DATA(gv_files)   = go_export->file_count( ).
  DATA(gv_failed)  = go_export->error_count( ).

  DATA(gv_zip) = go_export->archive( ).

  IF p_bytr = abap_true.
    WRITE: / 'Source          ', 'transport request', p_trkorr.
  ELSE.
    WRITE: / 'Source          ', 'package'.
  ENDIF.

  IF p_devc IS INITIAL.
    WRITE: / 'Root package    ', '(none) - paths use the full package chain'.
  ELSE.
    WRITE: / 'Root package    ', p_devc.
  ENDIF.

  WRITE: / 'Archive         ', gv_zip.

  IF p_bytr = abap_true.
    WRITE: / '                ', 'zgcts_push.ps1 -Zip <archive> -Repo <clone> -Push'.
  ELSE.
    WRITE: / '                ', 'zgcts_push.ps1 -Zip <archive> -Repo <clone> -Clean -Push'.
  ENDIF.
  WRITE: / 'Objects         ', gv_objects,
         / '  complete      ', gv_ok,
         / '  TADIR only    ', gv_partial,
         / '  skipped       ', gv_skipped,
         / 'Files written   ', gv_files,
         / '  write failed  ', gv_failed.
  SKIP.

  WRITE: / 'Type', 25 'Object', 90 'Tables', 100 'Files', 110 'Status', 125 'Note'.
  ULINE.

  LOOP AT gt_log INTO gs_log.
    WRITE: /  gs_log-object,
           25 gs_log-obj_name,
           90 gs_log-tables,
          100 gs_log-files,
          110 gs_log-status,
          125 gs_log-message.
  ENDLOOP.
