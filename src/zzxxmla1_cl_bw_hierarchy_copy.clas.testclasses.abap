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
    "! the copy is current only while BW's current row has the HIESID, SVER and TIMESTMP it is a copy of: BW does not
    "! change a structure once its SVER is written (switching the not-assigned node off makes a new SVER too), and the
    "! same SVER of another TIMESTMP is BW's SVER given again; a directory row never filled is not
    METHODS up_to_date FOR TESTING.
    "! a copy is kept while BW keeps its version, current or old, of the same TIMESTMP
    METHODS stale_copies FOR TESTING.
    "! a member's values are its rows of the closure the hierarchy is read from, of its HIESID and SVER
    METHODS values_of_member FOR TESTING.
    "! a hierarchy that shows the not-assigned node is read from the view, one that suppresses it from the table
    METHODS closure_read FOR TESTING.
    "! the not-assigned view: the table's rows, then per copy that shows the node the not-assigned node, the All
    "! member and the identity row of each SID under no leaf
    METHODS rest_view_source FOR TESTING.
    "! the generated objects are named by their prefixes and 7 digits, 16 characters as the DDIC allows
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
                      closure        = COND #( WHEN rest_shown = abap_true THEN 'ZZXXMLA1R0000001'
                                               ELSE 'ZZXXMLA1C0000001' )
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
    DATA(given_again) = VALUE zzxxmla1_hiedir( BASE directory timestmp = '20261001120000' ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_hierarchy_copy=>up_to_date( directory = given_again bw = bw ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_hierarchy_copy=>up_to_date(
      directory = VALUE #( hieid = 'TS4QSEWMTR32GXZQ0N46FIHRR' ) bw = bw ) ).
  ENDMETHOD.

  METHOD stale_copies.
    " COPY_OF_ZCLSERV_CAT: BW keeps SVER 1 and 2 (deleted) and 3 (current); the copy of SVER 2 is kept, the one of an
    " earlier use of SVER 3 and the one of a HIESID BW has no row of any more are not
    DATA(versions) = VALUE zzxxmla1_cl_bw_hierarchy_copy=>ty_t_version(
      ( hiesid = 246 sver = '1' timestmp = '20261015163612' )
      ( hiesid = 246 sver = '2' timestmp = '20261015163621' )
      ( hiesid = 246 sver = '3' timestmp = '20261015165533' ) ).
    DATA(copies) = VALUE zzxxmla1_cl_bw_hierarchy_copy=>ty_t_directory(
      ( hiesid = 246 sver = '2' timestmp = '20261015163621' )
      ( hiesid = 246 sver = '3' timestmp = '20261001120000' )
      ( hiesid = 245 sver = '1' timestmp = '20261001110000' ) ).
    DATA(stale) = zzxxmla1_cl_bw_hierarchy_copy=>stale_copies( copies = copies versions = versions ).
    cl_abap_unit_assert=>assert_equals( act = lines( stale ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = stale[ 1 ]-sver exp = '3' ).
    cl_abap_unit_assert=>assert_equals( act = stale[ 2 ]-hiesid exp = 245 ).
  ENDMETHOD.

  METHOD values_of_member.
    DATA(statement) = zzxxmla1_cl_bw_hierarchy_copy=>values_of( hierarchy = services( abap_false ) node_sid = -23 ).
    cl_abap_unit_assert=>assert_equals(
      act = statement-sql
      exp = `SELECT "SID" FROM "ZZXXMLA1C0000001" WHERE "HIESID" = ? AND "SVER" = ? AND "ANCESTOR_SID" = ?` ).
    cl_abap_unit_assert=>assert_equals( act = params( statement ) exp = VALUE string_table( ( `246` ) ( `3` ) ( `-23` ) ) ).
    " a leaf: its identity row
    statement = zzxxmla1_cl_bw_hierarchy_copy=>values_of( hierarchy = services( abap_true ) node_sid = 7 ).
    cl_abap_unit_assert=>assert_equals(
      act = statement-sql
      exp = `SELECT "SID" FROM "ZZXXMLA1R0000001" WHERE "HIESID" = ? AND "SVER" = ? AND "ANCESTOR_SID" = ?` ).
    cl_abap_unit_assert=>assert_equals( act = params( statement ) exp = VALUE string_table( ( `246` ) ( `3` ) ( `7` ) ) ).
  ENDMETHOD.

  METHOD closure_read.
    DATA(tables) = zzxxmla1_cl_bw_hierarchy_copy=>tables_of_number( 1 ).
    DATA(directory) = VALUE zzxxmla1_hiedir( hiesid = 246 sver = '3' root_sid = -19 rest_top_sid = -35 ).
    DATA(shown) = zzxxmla1_cl_bw_hierarchy_copy=>hierarchy_of( directory = directory tables = tables ).
    cl_abap_unit_assert=>assert_equals( act = shown-closure exp = 'ZZXXMLA1R0000001' ).
    cl_abap_unit_assert=>assert_true( shown-rest_shown ).
    DATA(suppressed) = zzxxmla1_cl_bw_hierarchy_copy=>hierarchy_of(
      directory = VALUE #( BASE directory norestnodes = abap_true ) tables = tables ).
    cl_abap_unit_assert=>assert_equals( act = suppressed-closure exp = 'ZZXXMLA1C0000001' ).
    cl_abap_unit_assert=>assert_false( suppressed-rest_shown ).
  ENDMETHOD.

  METHOD rest_view_source.
    DATA(nl) = cl_abap_char_utilities=>newline.
    DATA(rest) = ``.
    DATA(ancestors) = VALUE string_table( ( `d.rest_top_sid` ) ( `d.root_sid` ) ( `s.sid` ) ).
    LOOP AT ancestors INTO DATA(ancestor).
      rest = rest &&
             `union all select from zzxxmla1_hiedir as d` && nl &&
             `  inner join /bic/sztest as s on s.sid > d.root_sid` && nl &&
             `  left outer join zzxxmla1c0000007 as r on r.hiesid = d.hiesid and r.sver = d.sver ` &&
             `and r.ancestor_sid = d.root_sid and r.sid = s.sid` && nl &&
             `{` && nl && `  d.hiesid,` && nl && `  d.sver,` && nl &&
             |  { ancestor } as ancestor_sid,| && nl && `  s.sid` && nl && `}` && nl &&
             `where d.iobjnm = 'ZTEST' and d.norestnodes <> 'X' and r.sid is null` && nl.
    ENDLOOP.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_hierarchy_copy=>rest_view_source(
              characteristic = 'ZTEST'
              tables         = zzxxmla1_cl_bw_hierarchy_copy=>tables_of_number( 7 )
              sid_table      = '/BIC/SZTEST' )
      exp = `@AbapCatalog.sqlViewName: 'ZZXXMLA1R0000007'` && nl &&
            `@AbapCatalog.compiler.compareFilter: true` && nl &&
            `@AccessControl.authorizationCheck: #NOT_REQUIRED` && nl &&
            `@EndUserText.label: 'BW hierarchy closure ZTEST: with not assigned'` && nl &&
            `define view ZZXXMLA1_R0000007` && nl &&
            `  as select from zzxxmla1c0000007 as c` && nl &&
            `{` && nl && `  c.hiesid,` && nl && `  c.sver,` && nl && `  c.ancestor_sid,` && nl && `  c.sid` && nl &&
            `}` && nl && rest ).
  ENDMETHOD.

  METHOD table_names.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_hierarchy_copy=>table_name( prefix = zzxxmla1_cl_bw_hierarchy_copy=>c_node_prefix
                                                       number = 42 )
      exp = 'ZZXXMLA1H0000042' ).
    DATA(tables) = zzxxmla1_cl_bw_hierarchy_copy=>tables_of_number( 1 ).
    cl_abap_unit_assert=>assert_equals( act = tables-closure exp = 'ZZXXMLA1C0000001' ).
    cl_abap_unit_assert=>assert_equals( act = tables-rest_view exp = 'ZZXXMLA1R0000001' ).
    cl_abap_unit_assert=>assert_equals( act = tables-rest_ddl exp = 'ZZXXMLA1_R0000001' ).
  ENDMETHOD.

ENDCLASS.
