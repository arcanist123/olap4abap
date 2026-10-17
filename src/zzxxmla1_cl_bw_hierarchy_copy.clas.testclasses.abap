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
    "! a leaf is named and captioned by the view's columns, the initial value too (no #); the caption columns only
    "! with a caption column, REST_H's rows as wide as the others; a member's InfoObject per level
    METHODS leaf_names FOR TESTING.
    "! a node of an external characteristic is named and captioned by its view, on the SID BW gives it (VALUE_SID);
    "! without external characteristics the node table is read as it is
    METHODS external_node_names FOR TESTING.
    "! a text node is captioned by its text, the medium, else the long, else the short one, else its name; REST_H by
    "! the hierarchy's caption of it; without a caption column the node table is read as it is
    METHODS node_texts FOR TESTING.
    "! a hierarchy is offered per name and version, served if it has a slice valid to 9999-12-31, with the text of
    "! its latest slice (the version added where two versions have the same text); none with a time-dependent
    "! structure; its Hierarchy is named by the name and the version
    METHODS offered_slices FOR TESTING.
    METHODS params
      IMPORTING statement     TYPE zzxxmla1_cl_bw_hierarchy_copy=>ty_statement
      RETURNING VALUE(result) TYPE string_table.
ENDCLASS.

CLASS zzxxmla1_cl_bw_hierarchy_copy DEFINITION LOCAL FRIENDS ltc_bw_hierarchy_copy.

CLASS ltc_bw_hierarchy_copy IMPLEMENTATION.

  METHOD services.
    result = VALUE #( hieid          = 'HIEID_OF_ZCLSERV_CAT'
                      characteristic = 'ZCLSERV'
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

  METHOD offered_slices.
    DATA(rows) = VALUE zzxxmla1_cl_bw_hierarchy_copy=>ty_t_directory_text(
      ( hienm = 'ZCLDOC_ORG' version = '001' dateto = '20241231' txtmd = `Old Organization` )
      ( hienm = 'ZCLDOC_ORG' version = '001' dateto = '99991231' txtmd = `Clinic Organization` )
      ( hienm = 'ZCLDOC_ORG' version = '002' dateto = '99991231' txtmd = `Clinic Organization` )
      ( hienm = 'ZCLDOC_ORG' version = '003' dateto = '20241231' txtlg = `Ended` )
      ( hienm = 'ZCLDIAG_ICD' dateto = '99991231' txtsh = `Diagnoses` ) ).
    DATA(offered) = zzxxmla1_cl_bw_hierarchy_copy=>offer( rows = rows structure_time_dep = abap_false ).
    cl_abap_unit_assert=>assert_equals( exp = 4 act = lines( offered ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = VALUE zzxxmla1_cl_bw_hierarchy_copy=>ty_offered( name = `ZCLDIAG_ICD` hierarchy = `ZCLDIAG_ICD`
                                                             text = `Diagnoses` supported = abap_true )
      act = offered[ 1 ] ).
    cl_abap_unit_assert=>assert_equals(
      exp = VALUE zzxxmla1_cl_bw_hierarchy_copy=>ty_offered( name = `ZCLDOC_ORG` version = `001`
                                                             hierarchy = `ZCLDOC_ORG_001`
                                                             text = `Clinic Organization (001)` supported = abap_true )
      act = offered[ 2 ] ).
    cl_abap_unit_assert=>assert_equals( exp = `Clinic Organization (002)` act = offered[ 3 ]-text ).
    cl_abap_unit_assert=>assert_equals( exp = `Ended` act = offered[ 4 ]-text ).
    cl_abap_unit_assert=>assert_false( offered[ 4 ]-supported ).
    cl_abap_unit_assert=>assert_equals( exp = `it has no slice valid to 9999-12-31` act = offered[ 4 ]-reason ).
    offered = zzxxmla1_cl_bw_hierarchy_copy=>offer( rows = rows structure_time_dep = abap_true ).
    cl_abap_unit_assert=>assert_false( xsdbool( line_exists( offered[ supported = abap_true ] ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = `ZCLDIAG_ICD`
                                        act = zzxxmla1_cl_bw_hierarchy_copy=>hierarchy_name( name = 'ZCLDIAG_ICD' ) ).
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
                                             norestnodes = abap_true depth = 3 ).
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_bw_hierarchy_copy=>up_to_date( directory = directory bw = bw ) ).
    " a row written before the shape was kept
    DATA(without_shape) = VALUE zzxxmla1_hiedir( BASE directory depth = 0 ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_hierarchy_copy=>up_to_date( directory = without_shape bw = bw ) ).
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
    DATA(directory) = VALUE zzxxmla1_hiedir( hiesid = 246 sver = '3' root_sid = -19 rest_top_sid = -35
                                             depth = 4 repeated = `3 4` ).
    DATA(shown) = zzxxmla1_cl_bw_hierarchy_copy=>hierarchy_of( directory = directory tables = tables ).
    cl_abap_unit_assert=>assert_equals( act = shown-closure exp = 'ZZXXMLA1R0000001' ).
    cl_abap_unit_assert=>assert_true( shown-rest_shown ).
    " the shape from the directory row
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_hierarchy_copy=>depth( shown ) exp = 4 ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_bw_hierarchy_copy=>repeated_levels( shown )
                                        exp = VALUE int4_table( ( 3 ) ( 4 ) ) ).
    " at least 2 levels when the not-assigned node is shown
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_hierarchy_copy=>depth( VALUE #( BASE shown node_depth = 1 ) ) exp = 2 ).
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

  METHOD leaf_names.
    DATA(named) = zzxxmla1_cl_bw_hierarchy_copy=>levels_sql( hierarchy   = services( abap_true )
                                                              depth       = 3
                                                              value_table = `ZZXXMLA1V0000001`
                                                              sid_column  = `SID`
                                                              name_column = `ZCLSERV` ).
    cl_abap_unit_assert=>assert_char_np( act = named exp = `*'##'*` ).
    cl_abap_unit_assert=>assert_char_cp( act = named exp = `*COALESCE( TO_NVARCHAR( v."ZCLSERV" ), TO_NVARCHAR( n."SID" ) )*` ).
    cl_abap_unit_assert=>assert_char_np( act = named exp = `*CAPTION*` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = named
      exp = `*SELECT -35, 'REST_H', *, '1HIER_REST', CAST( NULL AS INTEGER ), *, CAST( NULL AS NVARCHAR( 1 ) ) FROM DUMMY*` ).
    " a member's InfoObject: a node's NODE_IOBJ, a leaf's the characteristic
    cl_abap_unit_assert=>assert_char_cp(
      act = named
      exp = `*CASE n."DEPTH" WHEN 1 THEN CASE WHEN n."SID" < 0 THEN TO_NVARCHAR( n."NODE_IOBJ" ) ELSE 'ZCLSERV' END ` &&
            `WHEN 2 THEN TO_NVARCHAR( p1."NODE_IOBJ" ) WHEN 3 THEN TO_NVARCHAR( p2."NODE_IOBJ" ) END AS "L01_IOBJ"*` ).

    DATA(captioned) = zzxxmla1_cl_bw_hierarchy_copy=>levels_sql( hierarchy      = services( abap_true )
                                                                  depth          = 3
                                                                  value_table    = `ZZXXMLA1V0000001`
                                                                  sid_column     = `SID`
                                                                  name_column    = `KEY_NAME`
                                                                  caption_column = `TXTMD` ).
    cl_abap_unit_assert=>assert_char_np( act = captioned exp = `*'##'*` ).
    cl_abap_unit_assert=>assert_char_cp( act = captioned exp = `*AS "L03_CAPTION", CASE n."DEPTH"* END AS "L03_IOBJ" FROM*` ).
    cl_abap_unit_assert=>assert_char_cp( act = captioned exp = `*COALESCE( TO_NVARCHAR( v."TXTMD" ), *` ).
    " REST_H and its values: SID, NAME, POS, CAPTION, IOBJ of level 1 and 2, then level 3 empty
    cl_abap_unit_assert=>assert_char_cp(
      act = captioned
      exp = `*SELECT -35, 'REST_H', *, 'REST_H', '1HIER_REST', CAST( NULL AS INTEGER ), CAST( NULL AS NVARCHAR( 1 ) ), ` &&
            `CAST( NULL AS INTEGER ), CAST( NULL AS NVARCHAR( 1 ) ), CAST( NULL AS NVARCHAR( 1 ) ), CAST( NULL AS INTEGER ), ` &&
            `CAST( NULL AS NVARCHAR( 1 ) ), CAST( NULL AS INTEGER ), CAST( NULL AS NVARCHAR( 1 ) ), ` &&
            `CAST( NULL AS NVARCHAR( 1 ) ) FROM DUMMY*` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = captioned
      exp = `*COALESCE( TO_NVARCHAR( v."TXTMD" ), COALESCE( TO_NVARCHAR( v."KEY_NAME" ), TO_NVARCHAR( r."SID" ) ) ), 'ZCLSERV', CAST( NULL*` ).
  ENDMETHOD.

  METHOD external_node_names.
    DATA(hierarchy) = services( abap_false ).
    hierarchy-externals = VALUE #( ( iobjnm = 'ZCLSITE' view = 'ZZXXMLA1V0000175' name_column = `ZCLSITE`
                                     caption_column = `TXTMD` )
                                   ( iobjnm = 'ZCLROOM' view = 'ZZXXMLA1V0000176' name_column = `COMPOUND_KEY`
                                     caption_column = `TXTMD` ) ).
    DATA(sql) = zzxxmla1_cl_bw_hierarchy_copy=>levels_sql( hierarchy      = hierarchy
                                                           depth          = 4
                                                           value_table    = `ZZXXMLA1V0000180`
                                                           sid_column     = `SID`
                                                           name_column    = `KEY_NAME`
                                                           caption_column = `TXTMD` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = sql
      exp = `*LEFT OUTER JOIN "ZZXXMLA1V0000176" AS x2 ON k."NODE_IOBJ" = 'ZCLROOM' AND x2."SID" = k."VALUE_SID"*` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = sql
      exp = `*COALESCE( TO_NVARCHAR( x1."ZCLSITE" ), TO_NVARCHAR( x2."COMPOUND_KEY" ), TO_NVARCHAR( k."NODE_NAME" ) ) AS "NODE_NAME"*` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = sql
      exp = `*COALESCE( TO_NVARCHAR( pv."TXTMD" ), TO_NVARCHAR( x1."TXTMD" ), TO_NVARCHAR( x2."TXTMD" ), NULLIF( t."TXTMD", '' ), ` &&
            `NULLIF( t."TXTLG", '' ), NULLIF( t."TXTSH", '' ), TO_NVARCHAR( k."NODE_NAME" ) ) AS "NODE_CAPTION"*` ).
    cl_abap_unit_assert=>assert_char_cp( act = sql exp = `*TO_NVARCHAR( p1."NODE_CAPTION" )*` ).

    DATA(plain) = zzxxmla1_cl_bw_hierarchy_copy=>levels_sql( hierarchy   = services( abap_false )
                                                             depth       = 4
                                                             value_table = `ZZXXMLA1V0000180`
                                                             sid_column  = `SID`
                                                             name_column = `KEY_NAME` ).
    cl_abap_unit_assert=>assert_char_np( act = plain exp = `*NODE_CAPTION*` ).
    cl_abap_unit_assert=>assert_char_np( act = plain exp = `*RSTHIERNODE*` ).
    cl_abap_unit_assert=>assert_char_cp( act = plain exp = `*FROM "ZZXXMLA1H0000001" AS n *` ).
  ENDMETHOD.

  METHOD node_texts.
    DATA(hierarchy) = services( abap_true ).
    hierarchy-rest_caption = `Not Assigned Service's (s)`.
    DATA(sql) = zzxxmla1_cl_bw_hierarchy_copy=>levels_sql( hierarchy      = hierarchy
                                                           depth          = 3
                                                           value_table    = `ZZXXMLA1V0000001`
                                                           sid_column     = `SID`
                                                           name_column    = `KEY_NAME`
                                                           caption_column = `TXTMD` ).
    " a text node's text of its hierarchy in English, matched by its node name
    cl_abap_unit_assert=>assert_char_cp(
      act = sql
      exp = `*AS k LEFT OUTER JOIN "RSTHIERNODE" AS t ON t."LANGU" = 'E' AND t."HIEID" = 'HIEID_OF_ZCLSERV_CAT' ` &&
            `AND t."OBJVERS" = 'A' AND k."NODE_IOBJ" = '0HIER_NODE' AND t."NODENAME" = k."NODE_NAME"*` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = sql
      exp = `*COALESCE( TO_NVARCHAR( pv."TXTMD" ), NULLIF( t."TXTMD", '' ), NULLIF( t."TXTLG", '' ), ` &&
            `NULLIF( t."TXTSH", '' ), TO_NVARCHAR( k."NODE_NAME" ) ) AS "NODE_CAPTION"*` ).
    " a postable node captioned as its value in the dimension's view
    cl_abap_unit_assert=>assert_char_cp(
      act = sql
      exp = `*LEFT OUTER JOIN "ZZXXMLA1V0000001" AS pv ON k."NODE_IOBJ" = 'ZCLSERV' AND pv."SID" = k."VALUE_SID"*` ).
    cl_abap_unit_assert=>assert_char_cp(
      act = sql
      exp = `*WHEN 1 THEN CASE WHEN n."SID" < 0 THEN TO_NVARCHAR( n."NODE_CAPTION" )*` ).
    " no COALESCE of one argument, which HANA refuses
    cl_abap_unit_assert=>assert_char_cp( act = sql exp = `*k."NODE_IOBJ", TO_NVARCHAR( k."NODE_NAME" ) AS "NODE_NAME", *` ).
    " the not-assigned node captioned as BW's MDX captions it, named REST_H
    cl_abap_unit_assert=>assert_char_cp( act = sql exp = `*SELECT -35, 'REST_H', *, 'Not Assigned Service''s (s)', '1HIER_REST'*` ).
  ENDMETHOD.

ENDCLASS.
