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
"! Creates the DDIC tables of the package (sapcli cannot export or import tables): run it with sapcli class execute.
"! ZZXXMLA1_FILE holds the server's files (ZZXXMLA1_CL_FILES); delivery class C, so its rows go to other systems as
"! table entries (R3TR TABU) in a transport.
CLASS zzxxmla1_cl_create_tables DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    "! Creates the tables that do not exist; the log, one line per table.
    METHODS run
      RETURNING VALUE(result) TYPE string_table.

  PRIVATE SECTION.
    CONSTANTS c_package TYPE devclass VALUE '$ZZXXMLA1'.

    TYPES:
      BEGIN OF ty_table,
        name TYPE tabname,
        text TYPE as4text,
      END OF ty_table,
      ty_t_table TYPE STANDARD TABLE OF ty_table WITH EMPTY KEY.

    METHODS tables RETURNING VALUE(result) TYPE ty_t_table.
    "! One line per field: table, K (key field) or - (other field), field name, type, length.
    "! A length of 0 means the type is a data element, except for STRG (a string).
    METHODS fields RETURNING VALUE(result) TYPE string_table.
    METHODS create_table IMPORTING table TYPE ty_table RETURNING VALUE(error) TYPE string.
    METHODS assign_to_package IMPORTING name TYPE tabname.
    METHODS build_fields IMPORTING name TYPE tabname RETURNING VALUE(result) TYPE dd03ptab.
ENDCLASS.

CLASS zzxxmla1_cl_create_tables IMPLEMENTATION.
  METHOD if_oo_adt_classrun~main.
    LOOP AT run( ) INTO DATA(line).
      out->write( line ).
    ENDLOOP.
  ENDMETHOD.

  METHOD run.
    " a table that exists is left as it is: it holds data (the server's files) that a new table would lose
    LOOP AT tables( ) INTO DATA(table).
      SELECT SINGLE tabname FROM dd02l WHERE tabname = @table-name INTO @DATA(existing).
      DATA(error) = COND string( WHEN sy-subrc <> 0 THEN create_table( table ) ).
      APPEND |{ table-name }: { COND string( WHEN existing IS NOT INITIAL THEN 'exists'
                                             WHEN error IS INITIAL THEN 'created'
                                             ELSE error ) }| TO result.
      CLEAR existing.
    ENDLOOP.
  ENDMETHOD.

  METHOD tables.
    result = VALUE #(
      ( name = 'ZZXXMLA1_FILE' text = 'XMLA server files (datasources.xml, schemas)' ) ).
  ENDMETHOD.

  METHOD fields.
    result = VALUE #(
      ( `ZZXXMLA1_FILE K PATH CHAR 255` )
      ( `ZZXXMLA1_FILE - CONTENT STRG 0` )
      ( `ZZXXMLA1_FILE - CHANGED_AT TIMESTAMPL 0` )
      ( `ZZXXMLA1_FILE - CHANGED_BY SYUNAME 0` ) ).
  ENDMETHOD.

  METHOD build_fields.
    LOOP AT fields( ) INTO DATA(line).
      SPLIT line AT ` ` INTO DATA(table) DATA(key) DATA(field) DATA(type) DATA(length).
      IF table <> name.
        CONTINUE.
      ENDIF.
      DATA(row) = VALUE dd03p( tabname   = name
                               fieldname = field
                               ddlanguage = sy-langu
                               position  = lines( result ) + 1
                               keyflag   = COND #( WHEN key = 'K' THEN abap_true )
                               notnull   = COND #( WHEN key = 'K' THEN abap_true ) ).
      IF type = 'STRG'.
        row-datatype = type.
        row-inttype  = 'g'.
        row-intlen   = 8.
      ELSEIF length = '0'.
        row-rollname = type.
        row-comptype = 'E'.
      ELSE.
        row-datatype = type.
        row-leng     = length.
        row-inttype  = SWITCH #( type WHEN 'NUMC' THEN 'N' ELSE 'C' ).
        row-intlen   = length * 2.
      ENDIF.
      APPEND row TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD assign_to_package.
    SELECT SINGLE obj_name FROM tadir
      WHERE pgmid = 'R3TR' AND object = 'TABL' AND obj_name = @name
      INTO @DATA(existing).
    IF sy-subrc = 0.
      RETURN.
    ENDIF.
    CALL FUNCTION 'TR_TADIR_INTERFACE'
      EXPORTING
        wi_test_modus       = abap_false
        wi_tadir_pgmid      = 'R3TR'
        wi_tadir_object     = 'TABL'
        wi_tadir_obj_name   = CONV tadir-obj_name( name )
        wi_tadir_author     = sy-uname
        wi_tadir_devclass   = c_package
        wi_tadir_masterlang = sy-langu
      EXCEPTIONS
        OTHERS              = 1.
  ENDMETHOD.

  METHOD create_table.
    DATA(dd02v) = VALUE dd02v( tabname    = table-name
                               ddlanguage = sy-langu
                               ddtext     = table-text
                               tabclass   = 'TRANSP'
                               contflag   = 'C'
                               exclass    = '1'
                               masterlang = sy-langu ).
    DATA(dd09l) = VALUE dd09v( tabname    = table-name
                               as4local   = 'A'
                               tabkat     = 0
                               tabart     = 'APPL0'
                               bufallow   = 'N'
                               roworcolst = 'C' ).
    DATA(dd03p) = build_fields( table-name ).
    IF dd03p IS INITIAL.
      error = 'no fields defined'.
      RETURN.
    ENDIF.

    assign_to_package( table-name ).

    CALL FUNCTION 'DDIF_TABL_PUT'
      EXPORTING
        name              = table-name
        dd02v_wa          = dd02v
        dd09l_wa          = dd09l
      TABLES
        dd03p_tab         = dd03p
      EXCEPTIONS
        tabl_not_found    = 1
        name_inconsistent = 2
        tabl_inconsistent = 3
        put_failure       = 4
        put_refused       = 5
        OTHERS            = 6.
    IF sy-subrc <> 0.
      error = |put failed, subrc { sy-subrc }|.
      RETURN.
    ENDIF.

    DATA rc TYPE sy-subrc.
    CALL FUNCTION 'DDIF_TABL_ACTIVATE'
      EXPORTING
        name        = table-name
      IMPORTING
        rc          = rc
      EXCEPTIONS
        not_found   = 1
        put_failure = 2
        OTHERS      = 3.
    " rc 4 means activated with warnings
    IF sy-subrc <> 0 OR rc > 4.
      error = |activation failed, subrc { sy-subrc }, rc { rc }|.
    ENDIF.
  ENDMETHOD.
ENDCLASS.