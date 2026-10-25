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
CLASS ltc_bw_auth_sql DEFINITION DEFERRED.
CLASS zzxxmla1_cl_bw_auth_sql DEFINITION LOCAL FRIENDS ltc_bw_auth_sql.

"! The request, the statement and the answers of the check in HANA; whether it answers as BW does is
"! scripts/auth_check_test.py's (GET auth/check?engine=sql against reference/auth/).
CLASS ltc_bw_auth_sql DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    CONSTANTS c_doc TYPE rsiobjnm VALUE 'ZCLDOC'.
    CONSTANTS c_diag TYPE rsiobjnm VALUE 'ZCLDIAG'.

    "! BW's CP as LIKE: * %, + _, % _ \ escaped; leading digits apart for a NUMC key
    METHODS like_patterns FOR TESTING.
    "! the members once each in the order the product of the factors shows them first, of the authorization-relevant
    "! characteristics only; per tuple of a factor its members and the bits of its characteristics; a tuple without
    "! members has member 0
    METHODS request_of_factors FOR TESTING.
    "! a factor without tuples: nothing to combine, the members are still checked
    METHODS empty_factor FOR TESTING.
    "! the statement: the profile and request as derived tables with bound values, the lines expanded on the path
    "! tables of their copies, a combination branch per factor
    METHODS statement_shape FOR TESTING.
    "! members only: no combination branch; no copies: an empty path table
    METHODS members_only FOR TESTING.
    "! the statement's first row is the refusal, with BW's message of the member's reason
    METHODS answers FOR TESTING.

    METHODS profile
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth_sql=>ty_profile.
    METHODS value
      IMPORTING iobjnm        TYPE rsiobjnm DEFAULT c_doc
                !value        TYPE csequence
                named         TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_member.
ENDCLASS.


CLASS ltc_bw_auth_sql IMPLEMENTATION.

  METHOD profile.
    result = VALUE #(
      characteristics = VALUE #( ( c_diag ) ( c_doc ) )
      flats           = VALUE #( ( auth = 'ZA' iobjnm = c_diag all = abap_true aggregate = abap_true )
                                 ( auth = 'ZA' iobjnm = c_doc aggregate = abap_true
                                   ranges = VALUE #( ( sign = 'I' option = 'CP' low = `01*` ) ) ) )
      lines           = VALUE #( ( line       = VALUE #( auth = 'ZA' iobjnm = c_doc hienm = 'ZCLDOC_ORG' version = '001'
                                                         node_iobjnm = '0HIER_NODE' node = `GP` type = '1'
                                                         date = '20250101' )
                                   key_copy   = VALUE #( hiesid = 41 sver = `1` path = 'ZZXXMLA1P0000003' )
                                   value_copy = VALUE #( hiesid = 40 sver = `2` path = 'ZZXXMLA1P0000003' ) ) ) ).
  ENDMETHOD.

  METHOD value.
    result = VALUE #( iobjnm = iobjnm kind = zzxxmla1_cl_bw_auth=>c_kind-value value = value named = named ).
  ENDMETHOD.

  METHOD like_patterns.
    DATA(numc) = zzxxmla1_cl_bw_auth_sql=>like( `01*` ).
    cl_abap_unit_assert=>assert_equals( exp = `01%` act = numc-pattern ).
    cl_abap_unit_assert=>assert_equals( exp = `01` act = numc-number ).
    cl_abap_unit_assert=>assert_equals( exp = `%` act = numc-rest ).
    DATA(text) = zzxxmla1_cl_bw_auth_sql=>like( `A_B+%\*` ).
    cl_abap_unit_assert=>assert_equals( exp = `A\_B_\%\\%` act = text-pattern ).
    cl_abap_unit_assert=>assert_initial( text-number ).
    " only digits: no number of its own
    cl_abap_unit_assert=>assert_initial( zzxxmla1_cl_bw_auth_sql=>like( `0042` )-number ).
  ENDMETHOD.

  METHOD request_of_factors.
    DATA(left) = VALUE zzxxmla1_cl_bw_auth=>ty_selection(
      ( VALUE #( ( iobjnm = c_doc kind = zzxxmla1_cl_bw_auth=>c_kind-aggregate ) ) )
      ( VALUE #( ( value( `001` ) ) ( iobjnm = '0CALMONTH' kind = zzxxmla1_cl_bw_auth=>c_kind-value value = `199701` ) ) )
      ( VALUE #( ( value( `#` ) ) ) ) ).
    DATA(right) = VALUE zzxxmla1_cl_bw_auth=>ty_selection( ( VALUE #( ( value( iobjnm = c_diag value = `I10` ) )
                                                                      ( value( `001` ) ) ) )
                                                           ( VALUE #( ) ) ).
    DATA(request) = zzxxmla1_cl_bw_auth_sql=>request( characteristics = VALUE #( ( c_diag ) ( c_doc ) )
                                                      factors         = VALUE #( ( left ) ( right ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = request-factors ).
    " the product shows (All, I10 001), (All, -), (001, ...), (#, ...): the aggregate, I10, 001, #; 0CALMONTH is not
    " authorization relevant; 001 once; # matched as ''
    cl_abap_unit_assert=>assert_equals( exp = 4 act = lines( request-members ) ).
    cl_abap_unit_assert=>assert_equals( exp = `I10` act = request-members[ 2 ]-member-value ).
    cl_abap_unit_assert=>assert_equals( exp = `` act = request-members[ 4 ]-key ).
    cl_abap_unit_assert=>assert_equals( exp = `#` act = request-members[ 4 ]-member-value ).
    cl_abap_unit_assert=>assert_equals(
      exp = VALUE zzxxmla1_cl_bw_auth_sql=>ty_request_tuples(
              ( factor = 1 tuple = 1 member = 1 mask = 2 ) ( factor = 1 tuple = 2 member = 3 mask = 2 )
              ( factor = 1 tuple = 3 member = 4 mask = 2 )
              ( factor = 2 tuple = 1 member = 2 mask = 3 ) ( factor = 2 tuple = 1 member = 3 mask = 3 )
              ( factor = 2 tuple = 2 member = 0 mask = 0 ) )
      act = request-tuples ).
  ENDMETHOD.

  METHOD empty_factor.
    DATA(request) = zzxxmla1_cl_bw_auth_sql=>request(
      characteristics = VALUE #( ( c_doc ) )
      factors         = VALUE #( ( VALUE #( ( VALUE #( ( value( `001` ) ) ) ) ) ) ( VALUE #( ) ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = request-factors ).
    cl_abap_unit_assert=>assert_initial( request-tuples ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( request-members ) ).
  ENDMETHOD.

  METHOD statement_shape.
    DATA(request) = zzxxmla1_cl_bw_auth_sql=>request(
      characteristics = VALUE #( ( c_diag ) ( c_doc ) )
      factors         = VALUE #( ( VALUE #( ( VALUE #( ( value( `001` ) ) ) ) ( VALUE #( ( value( `002` ) ) ) ) ) )
                                 ( VALUE #( ( VALUE #( ( value( iobjnm = c_diag value = `I10` named = abap_true ) ) ) ) ) ) ) ).
    DATA(statement) = zzxxmla1_cl_bw_auth_sql=>check_statement( profile = profile( ) request = request ).
    DATA(sql) = statement-sql.
    cl_abap_unit_assert=>assert_char_cp( act = sql exp = `WITH q_m AS ( SELECT CAST( ? AS INTEGER ) AS "M", *` ).
    " the copies of the line, both of the path table of ZCLDOC
    cl_abap_unit_assert=>assert_char_cp(
      act = sql
      exp = `*q_x AS ( SELECT 'ZCLDOC' AS "IOBJ", x."HIESID", * FROM "ZZXXMLA1P0000003" AS x ` &&
            `WHERE ( x."HIESID" = 41 AND x."SVER" = '1' ) OR ( x."HIESID" = 40 AND x."SVER" = '2' ) )*` ).
    cl_abap_unit_assert=>assert_char_cp( act = sql exp = `*q_t1 AS (*q_k1 AS (*q_t2 AS (*q_k2 AS (*` ).
    cl_abap_unit_assert=>assert_char_cp( act = sql exp = `*BITAND( CAST( 3 - BITOR( c1."MASK", c2."MASK" ) AS BIGINT ), *` ).
    cl_abap_unit_assert=>assert_char_cp( act = sql exp = `* ORDER BY "PHASE" LIMIT 1` ).
    " members 3 x 8, flags 2 x 5, one range 9, the line on both copies 2 x 11, tuples (2 + 1) x 3
    cl_abap_unit_assert=>assert_equals( exp = 24 + 10 + 9 + 22 + 9 act = lines( statement-params ) ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = count( val = sql sub = `CAST( ? AS INTEGER ) AS "T"` ) ).
  ENDMETHOD.

  METHOD members_only.
    DATA(request) = zzxxmla1_cl_bw_auth_sql=>request( characteristics = VALUE #( ( c_doc ) )
                                                      members         = VALUE #( ( value( `001` ) ) ) ).
    DATA(profile) = VALUE zzxxmla1_cl_bw_auth_sql=>ty_profile(
      characteristics = VALUE #( ( c_doc ) )
      flats           = VALUE #( ( auth = 'ZA' iobjnm = c_doc ranges = VALUE #( ( sign = 'I' option = 'EQ' low = `002` ) ) ) ) ).
    DATA(sql) = zzxxmla1_cl_bw_auth_sql=>check_statement( profile = profile request = request )-sql.
    cl_abap_unit_assert=>assert_equals( exp = 0 act = count( val = sql sub = `q_t1` ) ).
    cl_abap_unit_assert=>assert_char_cp( act = sql exp = `*q_x AS ( SELECT CAST( NULL AS NVARCHAR( 30 ) ) AS "IOBJ", *WHERE 1 = 0 )*` ).
    cl_abap_unit_assert=>assert_char_cp( act = sql exp = `*q_h AS ( SELECT CAST( NULL AS NVARCHAR( 30 ) ) AS "A", *WHERE 1 = 0 )*` ).
  ENDMETHOD.

  METHOD answers.
    DATA(request) = zzxxmla1_cl_bw_auth_sql=>request(
      characteristics = VALUE #( ( c_doc ) )
      members         = VALUE #( ( value( value = `099` named = abap_true ) )
                                 ( iobjnm = c_doc kind = zzxxmla1_cl_bw_auth=>c_kind-node value = `GP` hienm = 'ZCLDOC_ORG'
                                   version = '001' node_iobjnm = '0HIER_NODE' ) ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = zzxxmla1_cl_bw_auth=>c_status-allowed
      act = zzxxmla1_cl_bw_auth_sql=>answer( rows = VALUE #( ) request = request )-status ).
    DATA(unknown) = zzxxmla1_cl_bw_auth_sql=>answer( rows = VALUE #( ( VALUE #( ( `1` ) ( `1` ) ( `VALUE` ) ) ) )
                                                     request = request ).
    cl_abap_unit_assert=>assert_equals( exp = zzxxmla1_cl_bw_auth=>c_status-unknown act = unknown-status ).
    cl_abap_unit_assert=>assert_equals( exp = `Value 099 for characteristic ZCLDOC unknown` act = unknown-message ).
    DATA(node) = zzxxmla1_cl_bw_auth_sql=>answer( rows = VALUE #( ( VALUE #( ( `1` ) ( `2` ) ( `NODE` ) ) ) )
                                                  request = request ).
    cl_abap_unit_assert=>assert_equals( exp = `Hierarchy node GP of ZCLDOC_ORG version 001 not authorized`
                                        act = node-message ).
    DATA(combination) = zzxxmla1_cl_bw_auth_sql=>answer( rows = VALUE #( ( VALUE #( ( `2` ) ( `0` ) ( `COMBINATION` ) ) ) )
                                                         request = request ).
    cl_abap_unit_assert=>assert_equals( exp = zzxxmla1_cl_bw_auth=>c_reason-combination act = combination-reason ).
    cl_abap_unit_assert=>assert_equals( exp = `You do not have sufficient authorization` act = combination-message ).
  ENDMETHOD.

ENDCLASS.
