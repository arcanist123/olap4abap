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
CLASS ltc_sql DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    "! numbers of the types the views and sums deliver, read as strings: a DECIMAL keeps its scale, as Java's
    "! BigDecimal.toString does
    METHODS number_texts FOR TESTING RAISING cx_static_check.
    METHODS quote FOR TESTING.
    "! a database error is ZZXXMLA1_CX_SQL with the statement
    METHODS error FOR TESTING.
ENDCLASS.

CLASS ltc_sql IMPLEMENTATION.

  METHOD number_texts.
    DATA(rows) = zzxxmla1_cl_sql=>query(
      sql     = `SELECT CAST( 1997 AS DECIMAL(31,0) ), CAST( 7 AS BIGINT ), CAST( 2.5 AS DECIMAL(28,6) ), ` &&
                `CAST( 0 AS DECIMAL(31,0) ), 'Store 1', N'' FROM DUMMY`
      columns = 6 ).
    cl_abap_unit_assert=>assert_equals( act = lines( rows ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = concat_lines_of( table = rows[ 1 ] sep = `|` )
                                        exp = `1997|7|2.500000|0|Store 1|` ).
  ENDMETHOD.

  METHOD error.
    TRY.
        zzxxmla1_cl_sql=>query( sql = `SELECT * FROM "NO_SUCH_TABLE_ZZXXMLA1"` columns = 1 ).
        cl_abap_unit_assert=>fail( `no exception` ).
      CATCH zzxxmla1_cx_sql INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( act = error->statement exp = `SELECT * FROM "NO_SUCH_TABLE_ZZXXMLA1"` ).
        cl_abap_unit_assert=>assert_char_cp( act = error->error_message exp = '*NO_SUCH_TABLE_ZZXXMLA1*' ).
    ENDTRY.
  ENDMETHOD.

  METHOD quote.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_sql=>quote( '/BIC/FZFMSALES' ) exp = `"/BIC/FZFMSALES"` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_sql=>quote( 'a"b' ) exp = `"a""b"` ).
  ENDMETHOD.

ENDCLASS.
