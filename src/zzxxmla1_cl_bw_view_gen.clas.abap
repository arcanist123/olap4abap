*----------------------------------------------------------------------------------------------------------------------*
* olap4abap - XMLA server with an MDX engine for SAP BW               https://github.com/arcanist123/olap4abap
* Copyright (c) 2026 the olap4abap authors
*
* This program and the accompanying materials are made available under the terms of the Eclipse Public License 2.0,
* which is available at https://www.eclipse.org/legal/epl-2.0/
* SPDX-License-Identifier: EPL-2.0
*
* olap4abap contains code derived from Mondrian (Eclipse Public License 1.0): Copyright (C) 1998-2005 Julian Hyde,
* Copyright (C) 2005-2021 Hitachi Vantara and others, Copyright (C) 2021-2025 Sergei Semenkov. See the NOTICE file.
*----------------------------------------------------------------------------------------------------------------------*
"! Generates the CDS views a schema names as the dimension tables of a BW cube (docs/bw-to-schema-mapping.md):
"! one view per characteristic, the SID table left-joined with the active time-independent attributes (OBJVERS 'A') on
"! the key, with the columns SID, the key and the attributes: every value with a SID is a row, with or without
"! attributes (BW keeps none for its time characteristics, whose attribute tables have only the initial row); NUMC columns are delivered as numbers (INT4 up to 9 digits,
"! INT8 up to 18, else DEC 31), the other columns as they are, all named without their namespace (/BIC/ or another).
"! The table and field names are BW's (RSD_CHKTAB_GET_FOR_CHA_BAS, RSDIOBJ-FIELDNM), never built: their prefix depends
"! on the namespace. A characteristic without attribute table gets a view of its SID table alone (SID and key).
"! A reference characteristic (RSDCHA-CHABASNM, 0SOLD_TO -> 0CUSTOMER) has no tables of its own: its view is one of
"! the basic characteristic's tables and key field, under its own name.
"! The views are DDIC-based CDS views, the kind NetWeaver 7.50 has, named by a number: database view ZZXXMLA1V and DDL
"! source ZZXXMLA1_C followed by the same 7 digits (a characteristic does not fit: 16 and 30 characters at most, and a
"! namespace has slashes). The database view is what the schema names. The DDL source's description names the
"! characteristic ("BW characteristic ZFMSTORE: ..."), so the view of a characteristic is found by it; a view keeps its
"! number when it is generated again, a new one gets the next free number. A source of an older name (ZZXXMLA1_C_
"! followed by the characteristic) gets its number's name when it is generated again.
CLASS zzxxmla1_cl_bw_view_gen DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    CONSTANTS c_package TYPE devclass VALUE '$ZZXXMLA1'.
    TYPES:
      BEGIN OF ty_view,
        characteristic TYPE rsiobjnm,
        ddl_name       TYPE ddlname,
        view_name      TYPE viewname,
      END OF ty_view,
      ty_t_view TYPE STANDARD TABLE OF ty_view WITH EMPTY KEY.
    TYPES:
      "! The tables of a characteristic and the field of its key in them; attributes is initial if the characteristic
      "! has no attribute table.
      BEGIN OF ty_tables,
        basic      TYPE rsiobjnm,   " whose tables they are: the characteristic, or the one it references
        sids       TYPE tabname,
        attributes TYPE tabname,
        key_field  TYPE fieldname,
      END OF ty_tables.
    TYPES:
      "! A column of the attribute table: DDIC field, data type and length.
      BEGIN OF ty_column,
        field    TYPE fieldname,
        datatype TYPE datatype_d,
        length   TYPE i,
      END OF ty_column,
      ty_t_column TYPE STANDARD TABLE OF ty_column WITH EMPTY KEY.

    "! Creates or updates the views of all characteristics of a cube, in the order of the cube.
    METHODS generate_cube
      IMPORTING cube          TYPE rsinfocube
      RETURNING VALUE(result) TYPE ty_t_view
      RAISING   cx_dd_ddl_exception.
    "! The database view of the characteristic's DDL source, if there is one; nothing is changed.
    METHODS existing_view
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE viewname.
    "! The table name a schema gives the view of a characteristic that is not generated yet (ZZXXMLA1_C_ followed by
    "! the characteristic): a name only for the schema, never one of the DDIC; accepting the schema generates the view
    "! and puts in its database view (ZZXXMLA1_CL_SCHEMA_API).
    CLASS-METHODS placeholder
      IMPORTING characteristic TYPE csequence
      RETURNING VALUE(result)  TYPE string.
    "! The characteristic of a placeholder, initial for any other name.
    CLASS-METHODS characteristic_of_placeholder
      IMPORTING table         TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! The view column of a table field: the field without its namespace (/BIC/ZFMSNAME -> ZFMSNAME).
    CLASS-METHODS view_column
      IMPORTING field         TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! BW's tables of a characteristic: SID table, attribute table (if it exists) and key field.
    METHODS tables
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_tables.
    "! The columns the view gets from the characteristic's tables, in table order: the attribute table's, or the key
    "! of the SID table if there is no attribute table.
    METHODS columns
      IMPORTING tables        TYPE ty_tables
      RETURNING VALUE(result) TYPE ty_t_column.
    "! Creates or updates the view of one characteristic and activates it.
    METHODS generate
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_view
      RAISING   cx_dd_ddl_exception.
    "! Deletes the view of a characteristic (DDL source and database view) if there is one: BW refuses to delete a
    "! characteristic whose data elements a view still uses. Returns whether there was one.
    METHODS delete
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE abap_bool
      RAISING   cx_dd_ddl_exception.
    "! The DDL source of the view of a characteristic with the columns of its attribute table (in table order), or
    "! of its SID table if it has no attribute table.
    METHODS ddl_source
      IMPORTING characteristic TYPE rsiobjnm
                view_name      TYPE viewname
                tables         TYPE ty_tables
                columns        TYPE ty_t_column
      RETURNING VALUE(result)  TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS c_view_prefix TYPE string VALUE `ZZXXMLA1V`.
    CONSTANTS c_ddl_prefix TYPE string VALUE `ZZXXMLA1_C`.
    CONSTANTS c_placeholder_prefix TYPE string VALUE `ZZXXMLA1_C_`.
    DATA handler TYPE REF TO if_dd_ddl_handler.
    "! the numbers handed out in this run, not yet in the DDIC
    DATA used_numbers TYPE STANDARD TABLE OF i WITH EMPTY KEY.

    METHODS ddl_handler
      RETURNING VALUE(result) TYPE REF TO if_dd_ddl_handler.
    "! The DDL source of the view of a database view: ZZXXMLA1_C and the view's number.
    CLASS-METHODS ddl_name
      IMPORTING view_name     TYPE viewname
      RETURNING VALUE(result) TYPE ddlname.
    "! The description of the DDL source of a characteristic's view, by which it is found.
    CLASS-METHODS description
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ddtext.
    "! The DDL source of the characteristic's view, found by its description; initial if there is none.
    METHODS existing_ddl_name
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ddlname.
    "! The database view of an existing DDL source if it follows the numbering, else the next free number.
    METHODS view_name_for
      IMPORTING ddl_name      TYPE ddlname
      RETURNING VALUE(result) TYPE viewname.
    "! The number of a name of prefix and 7 digits, 0 for any other name.
    CLASS-METHODS number_of
      IMPORTING name          TYPE csequence
                prefix        TYPE string
      RETURNING VALUE(result) TYPE i.
    METHODS table_columns
      IMPORTING table         TYPE tabname
      RETURNING VALUE(result) TYPE ty_t_column.
    "! The column expression: a NUMC field cast to a number, any other field as it is; source is the table's alias.
    METHODS column_expression
      IMPORTING column        TYPE ty_column
                source        TYPE string
      RETURNING VALUE(result) TYPE string.
ENDCLASS.

CLASS zzxxmla1_cl_bw_view_gen IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    TRY.
        LOOP AT generate_cube( 'ZFMSALES' ) INTO DATA(view).
          out->write( |{ view-characteristic }: { view-ddl_name } / { view-view_name }| ).
        ENDLOOP.
      CATCH cx_dd_ddl_exception INTO DATA(error).
        out->write( |error: { error->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.

  METHOD generate_cube.
    " the characteristics of the cube; the package dimension and other technical or time objects are not
    SELECT d~iobjnm FROM rsddimeiobj AS d
      INNER JOIN rsdiobj AS o ON o~iobjnm = d~iobjnm AND o~objvers = 'A'
      WHERE d~infocube = @cube AND d~objvers = 'A' AND o~iobjtp = 'CHA'
      ORDER BY d~dimension ASCENDING, d~posit ASCENDING
      INTO TABLE @DATA(characteristics).
    LOOP AT characteristics INTO DATA(characteristic).
      APPEND generate( characteristic-iobjnm ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD generate.
    result-characteristic = characteristic.
    DATA(tables) = tables( characteristic ).
    DATA(existing) = existing_ddl_name( characteristic ).
    result-view_name = view_name_for( existing ).
    result-ddl_name = ddl_name( result-view_name ).
    " an active source can rename neither itself nor its database view: a source of another name (an older one, or
    " one whose view is not numbered) is deleted, and its view is created again by the numbered source
    IF existing IS NOT INITIAL AND existing <> result-ddl_name.
      ddl_handler( )->delete( existing ).
    ENDIF.
    DATA(source) = ddl_source( characteristic = characteristic
                               view_name      = result-view_name
                               tables         = tables
                               columns        = columns( tables ) ).
    DATA(text) = description( characteristic ).
    ddl_handler( )->save( name         = result-ddl_name
                          put_state    = 'N'
                          ddddlsrcv_wa = VALUE #( ddlname    = result-ddl_name
                                                  ddlanguage = sy-langu
                                                  ddtext     = text
                                                  source     = source ) ).
    cl_dd_ddl_handler=>if_dd_ddl_handler~write_tadir( objectname = result-ddl_name
                                                      devclass   = c_package
                                                      prid       = -1 ).
    ddl_handler( )->activate( result-ddl_name ).
  ENDMETHOD.

  METHOD delete.
    DATA(ddl_name) = existing_ddl_name( characteristic ).
    result = xsdbool( ddl_name IS NOT INITIAL ).
    IF result = abap_true.
      ddl_handler( )->delete( ddl_name ).
    ENDIF.
  ENDMETHOD.

  METHOD ddl_source.
    DATA(nl) = cl_abap_char_utilities=>newline.
    DATA(key) = to_lower( tables-key_field ).
    result = |@AbapCatalog.sqlViewName: '{ view_name }'| && nl &&
             |@AbapCatalog.compiler.compareFilter: true| && nl &&
             |@AccessControl.authorizationCheck: #NOT_REQUIRED| && nl &&
             |@EndUserText.label: '{ description( characteristic ) }'| && nl &&
             |define view { ddl_name( view_name ) }| && nl &&
             |  as select from { to_lower( tables-sids ) } as s| && nl.
    DATA(source) = `s`.
    IF tables-attributes IS NOT INITIAL.
      source = `p`.
      result = result &&
               |    left outer join { to_lower( tables-attributes ) } as p on  p.{ key } = s.{ key }| && nl &&
               |                                        and p.objvers = 'A'| && nl.
    ENDIF.
    result = result && |\{| && nl && |  key s.sid as SID|.
    LOOP AT columns INTO DATA(column) WHERE field <> 'OBJVERS' AND field <> 'CHANGED'.
      " the key from the SID table: the attribute table's is null where a value has no attributes
      result = result && |,| && nl &&
               |      { column_expression( column = column
                                           source = COND #( WHEN column-field = tables-key_field THEN `s` ELSE source ) ) }| &&
               | as { view_column( column-field ) }|.
    ENDLOOP.
    result = result && nl && |\}| && nl.
  ENDMETHOD.

  METHOD column_expression.
    DATA(field) = |{ source }.{ to_lower( column-field ) }|.
    IF column-datatype <> 'NUMC'.
      result = field.
    ELSEIF column-length <= 9.
      result = |cast( { field } as abap.int4 )|.
    ELSEIF column-length <= 18.
      result = |cast( { field } as abap.int8 )|.
    ELSE.
      result = |cast( { field } as abap.dec(31,0) )|.
    ENDIF.
  ENDMETHOD.

  METHOD view_column.
    " a namespace is /NAME/: everything up to the second slash
    result = field.
    IF strlen( field ) > 1 AND field(1) = '/'.
      FIND FIRST OCCURRENCE OF '/' IN SECTION OFFSET 1 OF field MATCH OFFSET DATA(slash).
      IF sy-subrc = 0.
        result = substring( val = field off = slash + 1 ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD placeholder.
    result = |{ c_placeholder_prefix }{ characteristic }|.
  ENDMETHOD.

  METHOD characteristic_of_placeholder.
    DATA(length) = strlen( c_placeholder_prefix ).
    IF strlen( table ) > length AND substring( val = table len = length ) = c_placeholder_prefix.
      result = substring( val = table off = length ).
    ENDIF.
  ENDMETHOD.

  METHOD ddl_name.
    result = |{ c_ddl_prefix }{ substring( val = view_name off = strlen( c_view_prefix ) ) }|.
  ENDMETHOD.

  METHOD description.
    " at most 49 characters up to the colon, so the description of every characteristic is a different one
    result = |BW characteristic { characteristic }: SID with active attributes|.
  ENDMETHOD.

  METHOD existing_ddl_name.
    " a numbered source sorts before one of the older name (ZZXXMLA1_C_<characteristic>)
    DATA(text) = description( characteristic ).
    DATA(pattern) = |{ c_ddl_prefix }%|.
    SELECT t~ddlname FROM ddddlsrct AS t
      INNER JOIN ddddlsrc AS s ON s~ddlname = t~ddlname AND s~as4local = t~as4local
      WHERE t~ddtext = @text AND t~ddlname LIKE @pattern
      ORDER BY t~ddlname ASCENDING
      INTO TABLE @DATA(names).
    IF names IS NOT INITIAL.
      result = names[ 1 ]-ddlname.
    ENDIF.
  ENDMETHOD.

  METHOD tables.
    DATA sids       TYPE rssidtab.
    DATA attributes TYPE rschntab.
    " a reference characteristic (0SOLD_TO -> 0CUSTOMER) has no tables of its own: they and their key field are the
    " basic characteristic's
    SELECT SINGLE chabasnm FROM rsdcha WHERE chanm = @characteristic AND objvers = 'A' INTO @result-basic.
    IF result-basic IS INITIAL.
      result-basic = characteristic.
    ENDIF.
    CALL FUNCTION 'RSD_CHKTAB_GET_FOR_CHA_BAS'
      EXPORTING
        i_chabasnm = result-basic
      IMPORTING
        e_chntab   = attributes
        e_sidtab   = sids
      EXCEPTIONS
        name_error = 1
        OTHERS     = 2.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    SELECT SINGLE fieldnm FROM rsdiobj WHERE iobjnm = @result-basic AND objvers = 'A' INTO @result-key_field.
    SELECT SINGLE tabname FROM dd02l WHERE tabname = @sids AND as4local = 'A' INTO @result-sids.
    SELECT SINGLE tabname FROM dd02l WHERE tabname = @attributes AND as4local = 'A' INTO @result-attributes.
    " the key must be a column of both, else no view can join them
    DATA(sid_columns) = table_columns( result-sids ).
    IF NOT line_exists( sid_columns[ field = result-key_field ] ).
      CLEAR result-sids.
    ENDIF.
    DATA(attribute_columns) = table_columns( result-attributes ).
    IF NOT line_exists( attribute_columns[ field = result-key_field ] ).
      CLEAR result-attributes.
    ENDIF.
  ENDMETHOD.

  METHOD columns.
    IF tables-attributes IS NOT INITIAL.
      result = table_columns( tables-attributes ).
    ELSE.
      LOOP AT table_columns( tables-sids ) INTO DATA(column) WHERE field = tables-key_field.
        APPEND column TO result.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD existing_view.
    DATA(ddl_name) = existing_ddl_name( characteristic ).
    IF ddl_name IS INITIAL.
      RETURN.
    ENDIF.
    TRY.
        ddl_handler( )->get_ddl_content_object_names( EXPORTING ddlname   = ddl_name
                                                                get_state = 'A'
                                                      IMPORTING viewname  = result ).
      CATCH cx_dd_ddl_read.
        CLEAR result.
    ENDTRY.
  ENDMETHOD.

  METHOD table_columns.
    SELECT fieldname, datatype, leng FROM dd03l
      WHERE tabname = @table AND as4local = 'A' AND fieldname NOT LIKE '.%'
      ORDER BY position ASCENDING
      INTO TABLE @DATA(fields).
    LOOP AT fields INTO DATA(field).
      APPEND VALUE #( field = field-fieldname datatype = field-datatype length = field-leng ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD view_name_for.
    IF ddl_name IS NOT INITIAL.
      TRY.
          ddl_handler( )->get_ddl_content_object_names( EXPORTING ddlname  = ddl_name
                                                                  get_state = 'A'
                                                        IMPORTING viewname = result ).
        CATCH cx_dd_ddl_read.
          CLEAR result.
      ENDTRY.
      IF number_of( name = result prefix = c_view_prefix ) > 0.
        RETURN.
      ENDIF.
    ENDIF.
    " the next number after the highest one in use by a database view or a DDL source
    DATA(highest) = 0.
    DATA(pattern) = |{ c_view_prefix }%|.
    SELECT tabname FROM dd02l WHERE tabname LIKE @pattern AND as4local = 'A' INTO TABLE @DATA(views).
    LOOP AT views INTO DATA(view).
      highest = nmax( val1 = highest val2 = number_of( name = view-tabname prefix = c_view_prefix ) ).
    ENDLOOP.
    pattern = |{ c_ddl_prefix }%|.
    SELECT ddlname FROM ddddlsrc WHERE ddlname LIKE @pattern INTO TABLE @DATA(sources).
    LOOP AT sources INTO DATA(source).
      highest = nmax( val1 = highest val2 = number_of( name = source-ddlname prefix = c_ddl_prefix ) ).
    ENDLOOP.
    LOOP AT used_numbers INTO DATA(used) WHERE table_line > highest.
      highest = used.
    ENDLOOP.
    highest = highest + 1.
    APPEND highest TO used_numbers.
    result = |{ c_view_prefix }{ highest WIDTH = 7 ALIGN = RIGHT PAD = '0' }|.
  ENDMETHOD.

  METHOD number_of.
    DATA(length) = strlen( prefix ).
    IF strlen( name ) = length + 7 AND substring( val = name len = length ) = prefix.
      DATA(digits) = substring( val = name off = length ).
      IF digits CO '0123456789'.
        result = digits.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD ddl_handler.
    IF handler IS NOT BOUND.
      handler = cl_dd_ddl_handler_factory=>create( ).
    ENDIF.
    result = handler.
  ENDMETHOD.

ENDCLASS.
