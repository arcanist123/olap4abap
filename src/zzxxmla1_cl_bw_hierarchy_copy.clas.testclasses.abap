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
CLASS ltc_bw_hierarchy_copy DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    TYPES ty_hierarchy TYPE zzxxmla1_cl_bw_hierarchy_copy=>ty_hierarchy.

    "! COPY_OF_ZCLSERV_CAT of the clinic demo: virtual root -19, not-assigned node -35
    METHODS services
      IMPORTING rest_shown    TYPE abap_bool
      RETURNING VALUE(result) TYPE ty_hierarchy.
    "! the copy is current only while BW's current row has the HIESID and SVER it is a copy of: BW does not change a
    "! structure once its SVER is written (switching the not-assigned node off makes a new SVER too); a directory row
    "! never filled is not
    METHODS up_to_date FOR TESTING.
    "! a node's values are its closure rows, of the hierarchy's HIESID and SVER
    METHODS values_of_node FOR TESTING.
    "! the not-assigned node's values are read live: the SID table's values under no leaf of the copy
    METHODS values_of_not_assigned FOR TESTING.
    "! the All member is every value while the not-assigned node is shown, else the values below its leaves
    METHODS values_of_all FOR TESTING.
    "! the generated tables are named by the prefix and 7 digits, 16 characters as the DDIC allows
    METHODS table_names FOR TESTING.
    METHODS params
      IMPORTING statement     TYPE zzxxmla1_cl_bw_hierarchy_copy=>ty_statement
      RETURNING VALUE(result) TYPE string_table.
ENDCLASS.

CLASS zzxxmla1_cl_bw_hierarchy_copy DEFINITION LOCAL FRIENDS ltc_bw_hierarchy_copy.

CLASS ltc_bw_hierarchy_copy IMPLEMENTATION.

  METHOD services.
    result = VALUE #( characteristic = 'ZCLSERV'
                      name           = 'COPY_OF_ZCLSERV_CAT'
                      node_table     = 'ZZXXMLA1H0000001'
                      closure_table  = 'ZZXXMLA1C0000001'
                      sid_table      = '/BIC/SZCLSERV'
                      hiesid         = 246
                      sver           = '3'
                      root_sid       = -19
                      rest_top_sid   = -35
                      rest_shown     = rest_shown ).
  ENDMETHOD.

  METHOD params.
    LOOP AT statement-params INTO DATA(param).
      ASSIGN param->* TO FIELD-SYMBOL(<value>).
      APPEND |{ <value> }| TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD up_to_date.
    DATA(bw) = VALUE zzxxmla1_cl_bw_hierarchy_copy=>ty_bw_state( hiesid = 246 sver = '3' timestmp = '20261015165533'
                                                                  norestnodes = abap_true ).
    DATA(directory) = VALUE zzxxmla1_hiedir( hiesid = 246 sver = '3' timestmp = '20261015165533'
                                             norestnodes = abap_true ).
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_bw_hierarchy_copy=>up_to_date( directory = directory bw = bw ) ).
    DATA(older) = VALUE zzxxmla1_hiedir( BASE directory sver = '2' timestmp = '20261015163621' ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_hierarchy_copy=>up_to_date( directory = older bw = bw ) ).
    DATA(other) = VALUE zzxxmla1_hiedir( BASE directory hiesid = 237 ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_hierarchy_copy=>up_to_date( directory = other bw = bw ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_hierarchy_copy=>up_to_date(
      directory = VALUE #( hieid = 'TS4QSEWMTR32GXZQ0N46FIHRR' ) bw = bw ) ).
  ENDMETHOD.

  METHOD values_of_node.
    DATA(statement) = zzxxmla1_cl_bw_hierarchy_copy=>values_of( hierarchy = services( abap_true ) node_sid = -23 ).
    cl_abap_unit_assert=>assert_equals(
      act = statement-sql
      exp = `SELECT "SID" FROM "ZZXXMLA1C0000001" WHERE "HIESID" = ? AND "SVER" = ? AND "ANCESTOR_SID" = ?` ).
    cl_abap_unit_assert=>assert_equals( act = params( statement ) exp = VALUE string_table( ( `246` ) ( `3` ) ( `-23` ) ) ).
  ENDMETHOD.

  METHOD values_of_not_assigned.
    DATA(statement) = zzxxmla1_cl_bw_hierarchy_copy=>values_of( hierarchy = services( abap_true ) node_sid = -35 ).
    cl_abap_unit_assert=>assert_equals(
      act = statement-sql
      exp = `SELECT s."SID" FROM "/BIC/SZCLSERV" AS s WHERE NOT EXISTS ( SELECT 1 FROM "ZZXXMLA1C0000001" AS c ` &&
            `WHERE c."HIESID" = ? AND c."SVER" = ? AND c."ANCESTOR_SID" = ? AND c."SID" = s."SID" )` ).
    cl_abap_unit_assert=>assert_equals( act = params( statement ) exp = VALUE string_table( ( `246` ) ( `3` ) ( `-19` ) ) ).
  ENDMETHOD.

  METHOD values_of_all.
    DATA(statement) = zzxxmla1_cl_bw_hierarchy_copy=>values_of( hierarchy = services( abap_true ) node_sid = -19 ).
    cl_abap_unit_assert=>assert_equals( act = statement-sql exp = `SELECT "SID" FROM "/BIC/SZCLSERV"` ).
    cl_abap_unit_assert=>assert_initial( statement-params ).
    statement = zzxxmla1_cl_bw_hierarchy_copy=>values_of( hierarchy = services( abap_false ) node_sid = -19 ).
    cl_abap_unit_assert=>assert_equals(
      act = statement-sql
      exp = `SELECT "SID" FROM "ZZXXMLA1C0000001" WHERE "HIESID" = ? AND "SVER" = ? AND "ANCESTOR_SID" = ?` ).
    cl_abap_unit_assert=>assert_equals( act = params( statement ) exp = VALUE string_table( ( `246` ) ( `3` ) ( `-19` ) ) ).
  ENDMETHOD.

  METHOD table_names.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_hierarchy_copy=>table_name( prefix = zzxxmla1_cl_bw_hierarchy_copy=>c_node_prefix
                                                       number = 42 )
      exp = 'ZZXXMLA1H0000042' ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_hierarchy_copy=>table_name( prefix = zzxxmla1_cl_bw_hierarchy_copy=>c_closure_prefix
                                                       number = 1 )
      exp = 'ZZXXMLA1C0000001' ).
  ENDMETHOD.

ENDCLASS.
