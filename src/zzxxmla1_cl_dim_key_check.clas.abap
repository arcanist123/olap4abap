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
"! Checks that the key of every dimension of a schema is unique in the dimension's table: the column the fact table's
"! foreign key refers to (ZZXXMLA1_CL_SCHEMA, ty_dim-key_column). A key value with several rows joins a fact row
"! several times, so every sum over that dimension counts the fact as often (the reference assumes the key is unique
"! and does not check it either). Per dimension the rows of the table, its distinct keys, the NULL keys (a NULL key
"! joins no fact; two of them are a duplicate too) and the most frequent duplicated keys; a table that several
"! dimensions use with the same key is read once.
CLASS zzxxmla1_cl_dim_key_check DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      "! the check of one dimension of a cube
      BEGIN OF ty_result,
        status          TYPE string,   " OK, DUPLICATES, NULL KEY or ERROR
        catalog         TYPE string,
        cube            TYPE string,
        dimension       TYPE string,
        dim_table       TYPE string,
        key_column      TYPE string,
        rows            TYPE int8,     " rows of the table
        keys            TYPE int8,     " distinct key values, without NULL
        null_keys       TYPE int8,     " rows whose key is NULL
        extra_rows      TYPE int8,     " rows beyond one per key value (NULL counted as one value)
        duplicated_keys TYPE int8,     " key values with more than one row, without NULL
        examples        TYPE string,   " the most frequent duplicated keys: key (rows), ...
        message         TYPE string,   " the database's error
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    CONSTANTS:
      BEGIN OF c_status,
        ok         TYPE string VALUE `OK`,
        duplicates TYPE string VALUE `DUPLICATES`,
        null_key   TYPE string VALUE `NULL KEY`,
        error      TYPE string VALUE `ERROR`,
      END OF c_status.
    "! how many duplicated keys are named per dimension
    CONSTANTS c_examples TYPE i VALUE 10.

    "! The dimensions of the schema file of the path (e.g. /WEB-INF/schema/FoodmartBW.xml), its catalog named by the
    "! path. ZZXXMLA1_CX_XMLA if the file does not exist or the schema cannot be read.
    METHODS check_file
      IMPORTING !path         TYPE csequence
      RETURNING VALUE(result) TYPE ty_t_result
      RAISING   zzxxmla1_cx_xmla.
    "! The dimensions of every catalog of the server.
    METHODS check_catalogs
      RETURNING VALUE(result) TYPE ty_t_result
      RAISING   zzxxmla1_cx_xmla.
    "! The dimensions of every cube of the schemas.
    METHODS check_schema
      IMPORTING !schema       TYPE REF TO zzxxmla1_cl_schema
      RETURNING VALUE(result) TYPE ty_t_result.

  PROTECTED SECTION.
  PRIVATE SECTION.
    "! the tables already read, with their result
    DATA checked TYPE ty_t_result.

    "! The check of a key column of a table, read from the database once per table and column.
    METHODS check_key
      IMPORTING dim_table     TYPE string
                key_column    TYPE string
      RETURNING VALUE(result) TYPE ty_result.
    "! rows, distinct keys and NULL keys of the table
    CLASS-METHODS counts_sql
      IMPORTING dim_table     TYPE string
                key_column    TYPE string
      RETURNING VALUE(result) TYPE string.
    "! the number of duplicated key values
    CLASS-METHODS duplicated_keys_sql
      IMPORTING dim_table     TYPE string
                key_column    TYPE string
      RETURNING VALUE(result) TYPE string.
    "! the most frequent duplicated keys with their rows, most rows first
    CLASS-METHODS examples_sql
      IMPORTING dim_table     TYPE string
                key_column    TYPE string
      RETURNING VALUE(result) TYPE string.
    "! The status and the extra rows of the counts.
    CLASS-METHODS evaluate
      CHANGING check TYPE ty_result.
    "! The rows of a duplicates query as key (rows), ...
    CLASS-METHODS examples_text
      IMPORTING !rows         TYPE zzxxmla1_cl_sql=>ty_t_row
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zzxxmla1_cl_dim_key_check IMPLEMENTATION.

  METHOD check_file.
    DATA(file) = zzxxmla1_cl_files=>read( path ).
    IF file-path IS INITIAL.
      zzxxmla1_cx_xmla=>raise_code( kind = `Client` code = `00HSBB01` text = `XMLA SOAP Body processing error`
                                    description = |The schema file { path } does not exist| ).
    ENDIF.
    result = check_schema( zzxxmla1_cl_schema=>of_catalogs(
      VALUE #( ( name = file-path schema = file-content updated_at = file-changed_at ) ) ) ).
  ENDMETHOD.

  METHOD check_catalogs.
    DATA(schema) = zzxxmla1_cl_schema=>get( ).
    schema->load( schema->catalogs( ) ).
    result = check_schema( schema ).
  ENDMETHOD.

  METHOD check_schema.
    LOOP AT schema->cubes( ) INTO DATA(cube).
      LOOP AT schema->dimensions( cube-cube_name ) INTO DATA(dimension).
        DATA(check) = check_key( dim_table = dimension-dim_table key_column = dimension-key_column ).
        check-catalog   = cube-catalog_name.
        check-cube      = cube-cube_name.
        check-dimension = dimension-dim_name.
        APPEND check TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_key.
    READ TABLE checked INTO result WITH KEY dim_table = dim_table key_column = key_column.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.
    result = VALUE #( dim_table = dim_table key_column = key_column ).
    TRY.
        DATA(counts) = zzxxmla1_cl_sql=>query( sql = counts_sql( dim_table = dim_table key_column = key_column )
                                               columns = 3 ).
        result-rows      = counts[ 1 ][ 1 ].
        result-keys      = counts[ 1 ][ 2 ].
        result-null_keys = counts[ 1 ][ 3 ].
        evaluate( CHANGING check = result ).
        IF result-rows - result-null_keys > result-keys.
          DATA(duplicated) = zzxxmla1_cl_sql=>query(
            sql     = duplicated_keys_sql( dim_table = dim_table key_column = key_column )
            columns = 1 ).
          result-duplicated_keys = duplicated[ 1 ][ 1 ].
          result-examples = examples_text( zzxxmla1_cl_sql=>query(
            sql     = examples_sql( dim_table = dim_table key_column = key_column )
            columns = 2 ) ).
        ENDIF.
      CATCH zzxxmla1_cx_sql INTO DATA(error).
        result-status  = c_status-error.
        result-message = error->error_message.
    ENDTRY.
    APPEND result TO checked.
  ENDMETHOD.

  METHOD counts_sql.
    DATA(column) = zzxxmla1_cl_sql=>quote( key_column ).
    result = |SELECT COUNT(*), COUNT( DISTINCT { column } ), COUNT(*) - COUNT( { column } )| &&
             | FROM { zzxxmla1_cl_sql=>quote( dim_table ) }|.
  ENDMETHOD.

  METHOD duplicated_keys_sql.
    DATA(column) = zzxxmla1_cl_sql=>quote( key_column ).
    result = |SELECT COUNT(*) FROM ( SELECT { column } FROM { zzxxmla1_cl_sql=>quote( dim_table ) }| &&
             | WHERE { column } IS NOT NULL GROUP BY { column } HAVING COUNT(*) > 1 )|.
  ENDMETHOD.

  METHOD examples_sql.
    DATA(column) = zzxxmla1_cl_sql=>quote( key_column ).
    result = |SELECT TO_NVARCHAR( { column } ), COUNT(*) FROM { zzxxmla1_cl_sql=>quote( dim_table ) }| &&
             | WHERE { column } IS NOT NULL GROUP BY { column } HAVING COUNT(*) > 1| &&
             | ORDER BY COUNT(*) DESC, { column } ASC LIMIT { c_examples }|.
  ENDMETHOD.

  METHOD evaluate.
    " the NULL keys are one value, as the reference's SQL groups them
    check-extra_rows = check-rows - check-keys - COND int8( WHEN check-null_keys > 0 THEN 1 ELSE 0 ).
    IF check-extra_rows > 0.
      check-status = c_status-duplicates.
    ELSEIF check-null_keys > 0.
      check-status = c_status-null_key.
    ELSE.
      check-status = c_status-ok.
    ENDIF.
  ENDMETHOD.

  METHOD examples_text.
    DATA(texts) = VALUE string_table( ).
    LOOP AT rows INTO DATA(row).
      APPEND |{ row[ 1 ] } ({ condense( row[ 2 ] ) })| TO texts.
    ENDLOOP.
    result = concat_lines_of( table = texts sep = `, ` ).
  ENDMETHOD.

ENDCLASS.
