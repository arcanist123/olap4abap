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
CLASS ltc_dim_key_check DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    "! one row per key: OK
    METHODS unique FOR TESTING.
    "! a key with three rows: two extra rows
    METHODS duplicates FOR TESTING.
    "! one NULL key is no duplicate, two are
    METHODS null_keys FOR TESTING.
    "! the statements run on HANA, against a table of the dictionary that is unique and one that is not
    METHODS statements FOR TESTING.
    METHODS examples_text FOR TESTING.
ENDCLASS.

CLASS zzxxmla1_cl_dim_key_check DEFINITION LOCAL FRIENDS ltc_dim_key_check.

CLASS ltc_dim_key_check IMPLEMENTATION.

  METHOD unique.
    DATA(check) = VALUE zzxxmla1_cl_dim_key_check=>ty_result( rows = 5 keys = 5 ).
    zzxxmla1_cl_dim_key_check=>evaluate( CHANGING check = check ).
    cl_abap_unit_assert=>assert_equals( act = check-status exp = zzxxmla1_cl_dim_key_check=>c_status-ok ).
    cl_abap_unit_assert=>assert_equals( act = check-extra_rows exp = 0 ).
  ENDMETHOD.

  METHOD duplicates.
    DATA(check) = VALUE zzxxmla1_cl_dim_key_check=>ty_result( rows = 7 keys = 5 ).
    zzxxmla1_cl_dim_key_check=>evaluate( CHANGING check = check ).
    cl_abap_unit_assert=>assert_equals( act = check-status exp = zzxxmla1_cl_dim_key_check=>c_status-duplicates ).
    cl_abap_unit_assert=>assert_equals( act = check-extra_rows exp = 2 ).
  ENDMETHOD.

  METHOD null_keys.
    DATA(check) = VALUE zzxxmla1_cl_dim_key_check=>ty_result( rows = 6 keys = 5 null_keys = 1 ).
    zzxxmla1_cl_dim_key_check=>evaluate( CHANGING check = check ).
    cl_abap_unit_assert=>assert_equals( act = check-status exp = zzxxmla1_cl_dim_key_check=>c_status-null_key ).
    check = VALUE #( rows = 7 keys = 5 null_keys = 2 ).
    zzxxmla1_cl_dim_key_check=>evaluate( CHANGING check = check ).
    cl_abap_unit_assert=>assert_equals( act = check-status exp = zzxxmla1_cl_dim_key_check=>c_status-duplicates ).
    cl_abap_unit_assert=>assert_equals( act = check-extra_rows exp = 1 ).
  ENDMETHOD.

  METHOD statements.
    DATA(check) = NEW zzxxmla1_cl_dim_key_check( ).
    " T000 has one row per client; DD03L one per field of a table
    DATA(unique) = check->check_key( dim_table = `T000` key_column = `MANDT` ).
    cl_abap_unit_assert=>assert_equals( act = unique-status exp = zzxxmla1_cl_dim_key_check=>c_status-ok ).
    cl_abap_unit_assert=>assert_equals( act = unique-rows exp = unique-keys ).
    DATA(duplicates) = check->check_key( dim_table = `DD03L` key_column = `TABNAME` ).
    cl_abap_unit_assert=>assert_equals( act = duplicates-status exp = zzxxmla1_cl_dim_key_check=>c_status-duplicates ).
    cl_abap_unit_assert=>assert_differs( act = duplicates-duplicated_keys exp = 0 ).
    cl_abap_unit_assert=>assert_not_initial( duplicates-examples ).
    DATA(error) = check->check_key( dim_table = `NO_SUCH_TABLE_ZZXXMLA1` key_column = `KEY` ).
    cl_abap_unit_assert=>assert_equals( act = error-status exp = zzxxmla1_cl_dim_key_check=>c_status-error ).
    cl_abap_unit_assert=>assert_char_cp( act = error-message exp = '*NO_SUCH_TABLE_ZZXXMLA1*' ).
  ENDMETHOD.

  METHOD examples_text.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_dim_key_check=>examples_text( VALUE #( ( VALUE #( ( `4711` ) ( `3` ) ) )
                                                               ( VALUE #( ( `A` ) ( `2` ) ) ) ) )
      exp = `4711 (3), A (2)` ).
  ENDMETHOD.

ENDCLASS.
