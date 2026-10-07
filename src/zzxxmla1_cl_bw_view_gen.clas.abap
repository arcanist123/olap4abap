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
"! Generates the CDS views a schema names as the dimension tables of a BW cube (docs/bw-schema-design-guide.md,
"! section 4): one view per basic characteristic, one row per SID. The SID table is left-outer-joined with everything
"! else, so every value with a SID is a row, with or without attributes (BW keeps none for its time characteristics,
"! whose attribute tables have only the initial row):
"! - the time-independent attributes (/BI0/P..., OBJVERS 'A') and the time-dependent ones (/BI0/Q..., OBJVERS 'A',
"!   valid on the key date 9999-12-31), joined on all their key fields;
"! - the texts of the characteristic and of every attribute that is a characteristic with texts (/BI0/T...), in
"!   language EN, valid on 9999-12-31, coalesce( text, key ) so that a value without text is named by its key. A text
"!   table is left out (a note) if it is client-dependent (the engine reads with native SQL, which filters no client,
"!   so a client-dependent table counts every fact once per client) or if a key field of it is not in the view.
"! The columns are SID, the key with its compounding (from the SID table), the characteristic's text (named like the
"! text field, TXTMD), then each attribute followed by its text (ATTRIBUTE_TXT). NUMC columns are delivered as
"! numbers (INT4 up to 9 digits, INT8 up to 18, else DEC 31), the other columns as they are, all named without their
"! namespace (/BIC/ or another). The table and field names are BW's (RSD_CHKTAB_GET_FOR_CHA_BAS, RSDIOBJ-FIELDNM),
"! never built: their prefix depends on the namespace.
"! A reference characteristic (RSDCHA-CHABASNM, 0SOLD_TO -> 0CUSTOMER) has no tables of its own: its view is the one of
"! the basic characteristic, which schemas name for both.
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
      "! The tables of a characteristic and the field of its key in them; a table is initial if the characteristic
      "! has none, or if the key field is not a column of it.
      BEGIN OF ty_tables,
        basic           TYPE rsiobjnm,   " whose tables they are: the characteristic, or the one it references
        sids            TYPE tabname,
        attributes      TYPE tabname,    " time-independent
        time_attributes TYPE tabname,    " time-dependent
        texts           TYPE tabname,
        key_field       TYPE fieldname,
      END OF ty_tables.
    TYPES:
      "! A column of a table: DDIC field, data type, length and whether it is a key field.
      BEGIN OF ty_column,
        field    TYPE fieldname,
        datatype TYPE datatype_d,
        length   TYPE i,
        key      TYPE abap_bool,
      END OF ty_column,
      ty_t_column TYPE STANDARD TABLE OF ty_column WITH EMPTY KEY.
    TYPES:
      "! A text table: its name, its columns and the field of the characteristic's value in it.
      BEGIN OF ty_text_table,
        name      TYPE tabname,
        key_field TYPE fieldname,
        columns   TYPE ty_t_column,
      END OF ty_text_table.
    TYPES:
      "! An attribute of the characteristic (RSDBCHATR): its field in the attribute tables, whether BW has it as a
      "! navigation attribute, and the text table of its characteristic (initial if it has none).
      BEGIN OF ty_attribute,
        iobjnm     TYPE rsiobjnm,
        field      TYPE fieldname,
        navigation TYPE abap_bool,
        texts      TYPE ty_text_table,
      END OF ty_attribute,
      ty_t_attribute TYPE STANDARD TABLE OF ty_attribute WITH EMPTY KEY.
    TYPES:
      "! What BW has of a characteristic, all its view is made of.
      BEGIN OF ty_metadata,
        characteristic         TYPE rsiobjnm,
        tables                 TYPE ty_tables,
        sid_columns            TYPE ty_t_column,
        attribute_columns      TYPE ty_t_column,
        time_attribute_columns TYPE ty_t_column,
        texts                  TYPE ty_text_table,
        attributes             TYPE ty_t_attribute,
      END OF ty_metadata.
    TYPES:
      "! A column of the view: its name, its expression in the DDL source, the DDIC type of the field it is made of
      "! (the view delivers a NUMC field as a number), the InfoObject whose value it is or, with text, whose text it is
      "! (initial for SID and compounding), and whether that is a navigation attribute in BW.
      BEGIN OF ty_view_column,
        name       TYPE string,
        expression TYPE string,
        datatype   TYPE string,
        length     TYPE i,
        iobjnm     TYPE string,
        text       TYPE abap_bool,
        navigation TYPE abap_bool,
      END OF ty_view_column,
      ty_t_view_column TYPE STANDARD TABLE OF ty_view_column WITH EMPTY KEY.
    TYPES:
      "! A left outer join of the view: table, alias and the conditions, combined with AND.
      BEGIN OF ty_join,
        table      TYPE tabname,
        alias      TYPE string,
        conditions TYPE string_table,
      END OF ty_join,
      ty_t_join TYPE STANDARD TABLE OF ty_join WITH EMPTY KEY.
    TYPES:
      "! Something BW has that the view leaves out, and why.
      BEGIN OF ty_note,
        iobjnm TYPE string,
        reason TYPE string,
      END OF ty_note,
      ty_t_note TYPE STANDARD TABLE OF ty_note WITH EMPTY KEY.
    TYPES:
      "! The view of a characteristic: its tables, the joins to its SID table (alias s), its columns and what it leaves
      "! out. No columns if the characteristic has no SID table.
      BEGIN OF ty_layout,
        tables  TYPE ty_tables,
        joins   TYPE ty_t_join,
        columns TYPE ty_t_view_column,
        notes   TYPE ty_t_note,
      END OF ty_layout.

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
    "! BW's tables of a characteristic and its key field.
    METHODS tables
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_tables.
    "! What BW has of a characteristic: tables, their columns, attributes and texts.
    METHODS metadata
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_metadata.
    "! The view of a characteristic as it is generated.
    METHODS layout
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_layout.
    "! The view made of a characteristic's metadata; reads nothing.
    CLASS-METHODS build_layout
      IMPORTING metadata      TYPE ty_metadata
      RETURNING VALUE(result) TYPE ty_layout.
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
    "! The DDL source of the view of a characteristic.
    CLASS-METHODS ddl_source
      IMPORTING characteristic TYPE rsiobjnm
                view_name      TYPE viewname
                layout         TYPE ty_layout
      RETURNING VALUE(result)  TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS c_view_prefix TYPE string VALUE `ZZXXMLA1V`.
    CONSTANTS c_ddl_prefix TYPE string VALUE `ZZXXMLA1_C`.
    CONSTANTS c_placeholder_prefix TYPE string VALUE `ZZXXMLA1_C_`.
    "! the language of the texts and the key date of time-dependent data (docs/bw-schema-design-guide.md, Scope)
    CONSTANTS c_language TYPE string VALUE `E`.
    CONSTANTS c_key_date TYPE string VALUE `99991231`.
    TYPES:
      "! a field the view can join on, and the alias of its table
      BEGIN OF ty_source,
        field TYPE fieldname,
        alias TYPE string,
      END OF ty_source,
      ty_t_source TYPE STANDARD TABLE OF ty_source WITH EMPTY KEY.
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
    "! The table if it is active and has the key field, else initial.
    METHODS usable_table
      IMPORTING table         TYPE tabname
                key_field     TYPE fieldname
      RETURNING VALUE(result) TYPE tabname.
    "! The text table of a characteristic's tables, initial if it has none.
    METHODS text_table
      IMPORTING tables        TYPE ty_tables
      RETURNING VALUE(result) TYPE ty_text_table.
    "! The column expression: a NUMC field cast to a number, any other field as it is; source is the table's alias.
    CLASS-METHODS column_expression
      IMPORTING column        TYPE ty_column
                source        TYPE string
      RETURNING VALUE(result) TYPE string.
    "! A field as text, for coalesce with a text: CHAR as it is, other character-like types cast; initial if the
    "! type cannot be cast.
    CLASS-METHODS as_text
      IMPORTING column        TYPE ty_column
                source        TYPE string
      RETURNING VALUE(result) TYPE string.
    "! The join of a text table to a value (value_source.value_field), in language EN at the key date; reason is set
    "! instead if the text table cannot be joined to one row per value.
    CLASS-METHODS text_join
      IMPORTING texts        TYPE ty_text_table
                alias        TYPE string
                value_field  TYPE fieldname
                value_source TYPE string
                sources      TYPE ty_t_source
      EXPORTING join         TYPE ty_join
                text_field   TYPE fieldname
                reason       TYPE string.
    "! The column of a text, joined to a value; a note if it cannot be.
    CLASS-METHODS add_text
      IMPORTING texts   TYPE ty_text_table
                iobjnm  TYPE csequence
                value   TYPE ty_column
                source  TYPE string
                name    TYPE string
                sources TYPE ty_t_source
      CHANGING  layout  TYPE ty_layout.
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
                               layout         = layout( characteristic ) ).
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

  METHOD layout.
    result = build_layout( metadata( characteristic ) ).
  ENDMETHOD.

  METHOD build_layout.
    result-tables = metadata-tables.
    IF metadata-tables-sids IS INITIAL.
      RETURN.
    ENDIF.
    DATA(key_field) = metadata-tables-key_field.

    " the fields joins can use: the key and its compounding from the SID table, the attributes from theirs
    DATA sources TYPE ty_t_source.
    LOOP AT metadata-sid_columns INTO DATA(column) WHERE key = abap_true.
      APPEND VALUE #( field = column-field alias = `s` ) TO sources.
    ENDLOOP.
    IF metadata-tables-attributes IS NOT INITIAL.
      DATA(join) = VALUE ty_join( table = metadata-tables-attributes alias = `p` ).
      LOOP AT metadata-attribute_columns INTO column WHERE key = abap_true AND field <> 'OBJVERS'.
        APPEND |p.{ to_lower( column-field ) } = s.{ to_lower( column-field ) }| TO join-conditions.
      ENDLOOP.
      APPEND |p.objvers = 'A'| TO join-conditions.
      APPEND join TO result-joins.
      LOOP AT metadata-attribute_columns INTO column WHERE key = abap_false AND field <> 'CHANGED'.
        APPEND VALUE #( field = column-field alias = `p` ) TO sources.
      ENDLOOP.
    ENDIF.
    IF metadata-tables-time_attributes IS NOT INITIAL.
      join = VALUE ty_join( table = metadata-tables-time_attributes alias = `q` ).
      LOOP AT metadata-time_attribute_columns INTO column
           WHERE key = abap_true AND field <> 'OBJVERS' AND field <> 'DATETO'.
        APPEND |q.{ to_lower( column-field ) } = s.{ to_lower( column-field ) }| TO join-conditions.
      ENDLOOP.
      APPEND |q.objvers = 'A'| TO join-conditions.
      APPEND |q.dateto = '{ c_key_date }'| TO join-conditions.
      APPEND join TO result-joins.
      LOOP AT metadata-time_attribute_columns INTO column
           WHERE key = abap_false AND field <> 'CHANGED' AND field <> 'DATEFROM'.
        APPEND VALUE #( field = column-field alias = `q` ) TO sources.
      ENDLOOP.
    ENDIF.

    " SID, the key with its compounding, the characteristic's text
    APPEND VALUE #( name = `SID` expression = `s.sid` datatype = `INT4` length = 10 ) TO result-columns.
    LOOP AT metadata-sid_columns INTO column WHERE key = abap_true.
      APPEND VALUE #( name       = view_column( column-field )
                      expression = column_expression( column = column source = `s` )
                      datatype   = column-datatype
                      length     = column-length
                      iobjnm     = COND #( WHEN column-field = key_field THEN metadata-tables-basic ) )
        TO result-columns.
    ENDLOOP.
    IF metadata-texts IS NOT INITIAL.
      add_text( EXPORTING texts   = metadata-texts
                          iobjnm  = metadata-tables-basic
                          value   = VALUE #( metadata-sid_columns[ field = key_field ] OPTIONAL )
                          source  = `s`
                          name    = ``
                          sources = sources
                CHANGING  layout  = result ).
    ENDIF.

    " each attribute, followed by its text
    LOOP AT sources INTO DATA(source) WHERE alias <> `s`.
      DATA(columns) = COND ty_t_column( WHEN source-alias = `p` THEN metadata-attribute_columns
                                        ELSE metadata-time_attribute_columns ).
      column = columns[ field = source-field ].
      DATA(attribute) = VALUE ty_attribute( metadata-attributes[ field = column-field ] OPTIONAL ).
      DATA(name) = view_column( column-field ).
      APPEND VALUE #( name       = name
                      expression = column_expression( column = column source = source-alias )
                      datatype   = column-datatype
                      length     = column-length
                      iobjnm     = attribute-iobjnm
                      navigation = attribute-navigation ) TO result-columns.
      IF attribute-texts IS NOT INITIAL.
        add_text( EXPORTING texts   = attribute-texts
                            iobjnm  = attribute-iobjnm
                            value   = column
                            source  = source-alias
                            name    = |{ name }_TXT|
                            sources = sources
                  CHANGING  layout  = result ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD add_text.
    DATA join TYPE ty_join.
    DATA text_field TYPE fieldname.
    DATA reason TYPE string.
    " the characteristic's text is t, the attributes' texts t1, t2, ...
    DATA(alias) = `t`.
    IF name IS NOT INITIAL.
      DATA(number) = 1.
      LOOP AT layout-joins TRANSPORTING NO FIELDS WHERE alias CP 't+*'.
        number = number + 1.
      ENDLOOP.
      alias = |t{ number }|.
    ENDIF.
    text_join( EXPORTING texts        = texts
                         alias        = alias
                         value_field  = value-field
                         value_source = source
                         sources      = sources
               IMPORTING join         = join
                         text_field   = text_field
                         reason       = reason ).
    DATA(column_name) = COND string( WHEN name IS INITIAL THEN view_column( text_field ) ELSE name ).
    IF reason IS INITIAL AND strlen( column_name ) > 30.
      reason = |text column { column_name } is longer than 30 characters|.
    ELSEIF reason IS INITIAL AND line_exists( layout-columns[ name = column_name ] ).
      reason = |text column { column_name } is the name of another column|.
    ENDIF.
    IF reason IS NOT INITIAL.
      APPEND VALUE #( iobjnm = iobjnm reason = |text not in the view: { reason }| ) TO layout-notes.
      RETURN.
    ENDIF.
    APPEND join TO layout-joins.
    DATA(text) = |{ alias }.{ to_lower( text_field ) }|.
    DATA(key) = as_text( column = value source = source ).
    APPEND VALUE #( name       = column_name
                    expression = COND #( WHEN key IS INITIAL THEN text ELSE |coalesce( { text }, { key } )| )
                    datatype   = `CHAR`
                    length     = texts-columns[ field = text_field ]-length
                    iobjnm     = iobjnm
                    text       = abap_true ) TO layout-columns.
  ENDMETHOD.

  METHOD text_join.
    CLEAR: join, text_field, reason.
    join = VALUE #( table = texts-name alias = alias ).
    LOOP AT texts-columns INTO DATA(column) WHERE key = abap_true.
      DATA(field) = |{ alias }.{ to_lower( column-field ) }|.
      IF column-datatype = 'CLNT'.
        reason = |{ texts-name } is client-dependent|.
        RETURN.
      ELSEIF column-field = texts-key_field.
        APPEND |{ field } = { value_source }.{ to_lower( value_field ) }| TO join-conditions.
      ELSEIF column-field = 'LANGU'.
        APPEND |{ field } = '{ c_language }'| TO join-conditions.
      ELSEIF column-field = 'DATETO'.
        APPEND |{ field } = '{ c_key_date }'| TO join-conditions.
      ELSE.
        " compounding: the same field of the view's tables
        READ TABLE sources INTO DATA(source) WITH KEY field = column-field.
        IF sy-subrc <> 0.
          reason = |key field { column-field } of { texts-name } is not in the view|.
          RETURN.
        ENDIF.
        APPEND |{ field } = { source-alias }.{ to_lower( column-field ) }| TO join-conditions.
      ENDIF.
    ENDLOOP.
    " the medium text, else the long, else the short one
    LOOP AT VALUE string_table( ( `TXTMD` ) ( `TXTLG` ) ( `TXTSH` ) ) INTO DATA(candidate).
      IF line_exists( texts-columns[ field = candidate key = abap_false ] ).
        text_field = candidate.
        RETURN.
      ENDIF.
    ENDLOOP.
    reason = |{ texts-name } has no text field|.
  ENDMETHOD.

  METHOD as_text.
    DATA(field) = |{ source }.{ to_lower( column-field ) }|.
    CASE column-datatype.
      WHEN 'CHAR'.
        result = field.
      WHEN 'NUMC' OR 'DATS' OR 'TIMS' OR 'CUKY' OR 'UNIT' OR 'LANG'.
        result = |cast( { field } as abap.char({ column-length }) )|.
    ENDCASE.
  ENDMETHOD.

  METHOD ddl_source.
    DATA(nl) = cl_abap_char_utilities=>newline.
    result = |@AbapCatalog.sqlViewName: '{ view_name }'| && nl &&
             |@AbapCatalog.compiler.compareFilter: true| && nl &&
             |@AccessControl.authorizationCheck: #NOT_REQUIRED| && nl &&
             |@EndUserText.label: '{ description( characteristic ) }'| && nl &&
             |define view { ddl_name( view_name ) }| && nl &&
             |  as select from { to_lower( layout-tables-sids ) } as s| && nl.
    LOOP AT layout-joins INTO DATA(join).
      LOOP AT join-conditions INTO DATA(condition).
        IF sy-tabix = 1.
          result = result && |    left outer join { to_lower( join-table ) } as { join-alias } on  { condition }| && nl.
        ELSE.
          result = result && |                                        and { condition }| && nl.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
    result = result && |\{| && nl.
    LOOP AT layout-columns INTO DATA(column).
      result = result && COND string( WHEN sy-tabix = 1 THEN `  key ` ELSE |,{ nl }      | ) &&
               |{ column-expression } as { column-name }|.
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
    DATA sids            TYPE rssidtab.
    DATA attributes      TYPE rschntab.
    DATA time_attributes TYPE rschttab.
    DATA texts           TYPE rstxttab.
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
        e_chttab   = time_attributes
        e_txttab   = texts
        e_sidtab   = sids
      EXCEPTIONS
        name_error = 1
        OTHERS     = 2.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    SELECT SINGLE fieldnm FROM rsdiobj WHERE iobjnm = @result-basic AND objvers = 'A' INTO @result-key_field.
    " the key must be a column of each, else no view can join them
    result-sids = usable_table( table = sids key_field = result-key_field ).
    result-attributes = usable_table( table = attributes key_field = result-key_field ).
    result-time_attributes = usable_table( table = time_attributes key_field = result-key_field ).
    result-texts = usable_table( table = texts key_field = result-key_field ).
  ENDMETHOD.

  METHOD usable_table.
    IF table IS INITIAL OR key_field IS INITIAL.
      RETURN.
    ENDIF.
    SELECT SINGLE fieldname FROM dd03l
      WHERE tabname = @table AND as4local = 'A' AND fieldname = @key_field
      INTO @DATA(found).
    IF sy-subrc = 0.
      result = table.
    ENDIF.
  ENDMETHOD.

  METHOD metadata.
    result-characteristic = characteristic.
    result-tables = tables( characteristic ).
    IF result-tables-sids IS INITIAL.
      RETURN.
    ENDIF.
    result-sid_columns = table_columns( result-tables-sids ).
    result-attribute_columns = table_columns( result-tables-attributes ).
    result-time_attribute_columns = table_columns( result-tables-time_attributes ).
    result-texts = text_table( result-tables ).
    " the attributes of the basic characteristic in BW's order; a characteristic among them has its own texts
    SELECT a~attrinm, a~attritp, o~fieldnm, o~iobjtp FROM rsdbchatr AS a
      INNER JOIN rsdiobj AS o ON o~iobjnm = a~attrinm AND o~objvers = 'A'
      WHERE a~chabasnm = @result-tables-basic AND a~objvers = 'A'
      ORDER BY a~posit ASCENDING
      INTO TABLE @DATA(attributes).
    LOOP AT attributes INTO DATA(attribute).
      APPEND VALUE #( iobjnm     = attribute-attrinm
                      field      = attribute-fieldnm
                      navigation = xsdbool( attribute-attritp = 'NAV' )
                      texts      = COND #( WHEN attribute-iobjtp = 'CHA' OR attribute-iobjtp = 'TIM'
                                           THEN text_table( tables( attribute-attrinm ) ) ) ) TO result-attributes.
    ENDLOOP.
  ENDMETHOD.

  METHOD text_table.
    IF tables-texts IS INITIAL.
      RETURN.
    ENDIF.
    result = VALUE #( name = tables-texts key_field = tables-key_field columns = table_columns( tables-texts ) ).
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
    IF table IS INITIAL.
      RETURN.
    ENDIF.
    SELECT fieldname, datatype, leng, keyflag FROM dd03l
      WHERE tabname = @table AND as4local = 'A' AND fieldname NOT LIKE '.%'
      ORDER BY position ASCENDING
      INTO TABLE @DATA(fields).
    LOOP AT fields INTO DATA(field).
      APPEND VALUE #( field    = field-fieldname
                      datatype = field-datatype
                      length   = field-leng
                      key      = xsdbool( field-keyflag = abap_true ) ) TO result.
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
