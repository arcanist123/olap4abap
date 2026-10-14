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
"! Native SQL on the database of the system (HANA) through ADBC, as the reference runs its SQL through JDBC: the engine
"! builds the statements itself (docs/mvp-scope.md, schema decision). Every column is read as a string; a number
"! arrives in its plain form with the scale of its type, as Java's BigDecimal.toString writes it (1997 for INTEGER or
"! DECIMAL(31,0), 2.500000 for 2.5 as DECIMAL(28,6)).
CLASS zzxxmla1_cl_sql DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_t_row TYPE STANDARD TABLE OF string_table WITH EMPTY KEY.

    "! The statements query has run since the last reset_statistics, and their time in microseconds (the trace of a
    "! call records them, ZZXXMLA1_CL_TRACE).
    CLASS-DATA statement_count TYPE i READ-ONLY.
    CLASS-DATA statement_time TYPE int8 READ-ONLY.
    "! Set: query keeps each statement with its rows and microseconds in statement_log (for measurements).
    CLASS-DATA log_statements TYPE abap_bool.
    TYPES:
      BEGIN OF ty_logged,
        sql  TYPE string,
        rows TYPE i,
        time TYPE int8,
      END OF ty_logged.
    CLASS-DATA statement_log TYPE STANDARD TABLE OF ty_logged WITH EMPTY KEY READ-ONLY.

    "! The rows of a query with the given number of columns, each row the values of its columns in order. A database
    "! error raises ZZXXMLA1_CX_SQL (unchecked).
    CLASS-METHODS query
      IMPORTING !sql          TYPE string
                !columns      TYPE i
      RETURNING VALUE(result) TYPE ty_t_row.
    "! Sets statement_count and statement_time to 0.
    CLASS-METHODS reset_statistics.
    "! An identifier as a quoted SQL identifier, e.g. "/BIC/FZFMSALES".
    CLASS-METHODS quote
      IMPORTING identifier    TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! A value as a SQL string literal, e.g. 'O''Brien'.
    CLASS-METHODS literal
      IMPORTING value         TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! The condition that a column holds a key as query reads it: equal to it, or for an empty key NULL or empty (a
    "! NULL column is read as an empty string; the column may be a number, so the empty case compares its text).
    CLASS-METHODS key_condition
      IMPORTING column        TYPE csequence
                key           TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! The condition that a column holds one of the keys (a ListColumnPredicate): key_condition for one key, else an IN
    "! list of the keys that are not empty, ORed with the empty case if one is.
    CLASS-METHODS keys_condition
      IMPORTING column        TYPE csequence
                keys          TYPE string_table
      RETURNING VALUE(result) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zzxxmla1_cl_sql IMPLEMENTATION.

  METHOD query.
    " the rows are fetched into a table of a structure with one string component per column
    DATA(components) = VALUE cl_abap_structdescr=>component_table( ).
    DO columns TIMES.
      APPEND VALUE #( name = |C{ sy-index }| type = cl_abap_elemdescr=>get_string( ) ) TO components.
    ENDDO.
    DATA(table_type) = cl_abap_tabledescr=>create( cl_abap_structdescr=>create( components ) ).
    DATA rows TYPE REF TO data.
    CREATE DATA rows TYPE HANDLE table_type.
    FIELD-SYMBOLS <rows> TYPE STANDARD TABLE.
    ASSIGN rows->* TO <rows>.

    GET RUN TIME FIELD DATA(started).
    TRY.
        DATA(statement) = NEW cl_sql_statement( ).
        DATA(result_set) = statement->execute_query( sql ).
        result_set->set_param_table( rows ).
        result_set->next_package( ).
        result_set->close( ).
      CATCH cx_sql_exception INTO DATA(error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_sql
          EXPORTING
            statement     = sql
            error_message = error->get_text( )
            previous      = error.
    ENDTRY.
    GET RUN TIME FIELD DATA(stopped).
    statement_count = statement_count + 1.
    statement_time = statement_time + stopped - started.
    IF log_statements = abap_true.
      APPEND VALUE #( sql = sql rows = lines( <rows> ) time = stopped - started ) TO statement_log.
    ENDIF.

    LOOP AT <rows> ASSIGNING FIELD-SYMBOL(<row>).
      DATA(values) = VALUE string_table( ).
      DO columns TIMES.
        ASSIGN COMPONENT sy-index OF STRUCTURE <row> TO FIELD-SYMBOL(<value>).
        APPEND <value> TO values.
      ENDDO.
      APPEND values TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD reset_statistics.
    CLEAR: statement_count, statement_time, statement_log.
  ENDMETHOD.

  METHOD quote.
    result = `"` && replace( val = identifier sub = `"` with = `""` occ = 0 ) && `"`.
  ENDMETHOD.

  METHOD literal.
    result = `'` && replace( val = value sub = `'` with = `''` occ = 0 ) && `'`.
  ENDMETHOD.

  METHOD key_condition.
    IF key IS INITIAL.
      result = |COALESCE( TO_NVARCHAR( { column } ), '' ) = ''|.
    ELSE.
      result = |{ column } = { literal( key ) }|.
    ENDIF.
  ENDMETHOD.

  METHOD keys_condition.
    IF lines( keys ) = 1.
      result = key_condition( column = column key = keys[ 1 ] ).
      RETURN.
    ENDIF.
    DATA(literals) = VALUE string_table( FOR k IN keys WHERE ( table_line IS NOT INITIAL ) ( literal( k ) ) ).
    DATA(conditions) = VALUE string_table( ).
    IF literals IS NOT INITIAL.
      APPEND |{ column } IN ( { concat_lines_of( table = literals sep = `, ` ) } )| TO conditions.
    ENDIF.
    IF line_exists( keys[ table_line = `` ] ).
      APPEND key_condition( column = column key = `` ) TO conditions.
    ENDIF.
    result = |( { concat_lines_of( table = conditions sep = ` OR ` ) } )|.
  ENDMETHOD.

ENDCLASS.
