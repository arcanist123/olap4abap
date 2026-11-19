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
"! scripts/auth_check_test.py's (GET auth/check?engine=sql against reference/auth/) and scripts/bw_auth_compare.py's.
CLASS ltc_bw_auth_sql DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    CONSTANTS c_doc TYPE rsiobjnm VALUE 'ZCLDOC'.
    CONSTANTS c_diag TYPE rsiobjnm VALUE 'ZCLDIAG'.

    "! BW's CP as LIKE: * %, + _, % _ \ escaped; leading digits apart for a NUMC key
    METHODS like_patterns FOR TESTING.
    "! the members once each in the order the product of the factors shows them first, of the authorization-relevant
    "! characteristics only, each at the position of its characteristic; the pairs of a factor are not kept
    METHODS request_of_factors FOR TESTING.
    "! a characteristic the factors have no member of is aggregated; a member the query only names is checked alone
    METHODS request_aggregates_and_named FOR TESTING.
    "! a factor without tuples: no product, no aggregate, the members are still checked
    METHODS empty_factor FOR TESTING.
    "! the statement: the named sections, the inputs as bound JSON, a branch per hierarchy characteristic's tables
    METHODS statement_shape FOR TESTING.
    "! the text is the same for any query, profile and copies of the provider: only the bound values differ
    METHODS same_text FOR TESTING.
    "! a provider without hierarchy characteristics: an empty path table, REST_H from the copies only
    METHODS no_hierarchy_tables FOR TESTING.
    "! the first refusal: a member before an aggregate, a named one first; else a combination without a common
    "! authorization; else allowed
    METHODS answers FOR TESTING.
    "! the search of a combination of classes without a common bit
    METHODS holes FOR TESTING.
    "! bound rows as one JSON parameter keyed by the columns' names: numbers as numbers, strings escaped; the
    "! statement's text the same for any number of rows, none included
    METHODS values_as_json FOR TESTING.

    METHODS profile
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth_sql=>ty_profile.
    METHODS value
      IMPORTING iobjnm        TYPE rsiobjnm DEFAULT c_doc
                !value        TYPE csequence
                named         TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_member.
    "! a row of the statement's answer
    METHODS row
      IMPORTING !type         TYPE csequence
                pos           TYPE i DEFAULT 0
                !mask         TYPE int8 DEFAULT 0
                m             TYPE i
                reason        TYPE csequence DEFAULT ``
      RETURNING VALUE(result) TYPE string_table.
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
                                   key_copy   = VALUE #( basic = c_doc hiesid = 41 sver = `1` )
                                   value_copy = VALUE #( basic = c_doc hiesid = 40 sver = `2` ) ) )
      tables          = VALUE #( ( basic = c_diag path = 'ZZXXMLA1P0000003' closure = 'ZZXXMLA1R0000003'
                                   sid_table = '/BIC/SZCLDIAG' leaf_name = `s."/BIC/ZCLDIAG"` )
                                 ( basic = c_doc path = 'ZZXXMLA1P0000002' closure = 'ZZXXMLA1R0000002'
                                   sid_table = '/BIC/SZCLDOC' leaf_name = `s."/BIC/ZCLDOC"` ) ) ).
  ENDMETHOD.

  METHOD value.
    result = VALUE #( iobjnm = iobjnm kind = zzxxmla1_cl_bw_auth=>c_kind-value value = value named = named ).
  ENDMETHOD.

  METHOD row.
    result = VALUE #( ( CONV string( type ) ) ( |{ pos }| ) ( |{ mask }| ) ( |{ m }| ) ( `1` ) ( CONV string( reason ) ) ).
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
    " CROSS's rows: the pairs (009, I10) and (012, J45); the product is {009, 012} x {I10, J45}
    DATA(rows) = VALUE zzxxmla1_cl_bw_auth=>ty_selection(
      ( VALUE #( ( value( `009` ) ) ( value( iobjnm = c_diag value = `I10` ) ) ) )
      ( VALUE #( ( value( `012` ) ) ( value( iobjnm = c_diag value = `J45` ) )
                 ( iobjnm = '0CALMONTH' kind = zzxxmla1_cl_bw_auth=>c_kind-value value = `199701` ) ) )
      ( VALUE #( ( value( `#` ) ) ) ) ).
    DATA(request) = zzxxmla1_cl_bw_auth_sql=>request( characteristics = VALUE #( ( c_diag ) ( c_doc ) )
                                                      factors         = VALUE #( ( rows ) ) ).
    cl_abap_unit_assert=>assert_true( request-product ).
    " 0CALMONTH is not authorization relevant; # matched as ''
    cl_abap_unit_assert=>assert_equals( exp = 5 act = lines( request-members ) ).
    cl_abap_unit_assert=>assert_equals( exp = `009` act = request-members[ 1 ]-member-value ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = request-members[ 1 ]-pos ).
    cl_abap_unit_assert=>assert_equals( exp = `I10` act = request-members[ 2 ]-member-value ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = request-members[ 2 ]-pos ).
    cl_abap_unit_assert=>assert_equals( exp = `` act = request-members[ 5 ]-key ).
    cl_abap_unit_assert=>assert_equals( exp = `#` act = request-members[ 5 ]-member-value ).
    " every characteristic has members: no aggregate
    cl_abap_unit_assert=>assert_false(
      xsdbool( line_exists( request-members[ member-kind = zzxxmla1_cl_bw_auth=>c_kind-aggregate ] ) ) ).
  ENDMETHOD.

  METHOD request_aggregates_and_named.
    DATA(slicer) = VALUE zzxxmla1_cl_bw_auth=>ty_selection( ( VALUE #( ( value( `001` ) ) ) ) ).
    DATA(node) = VALUE zzxxmla1_cl_bw_auth=>ty_member( iobjnm = c_doc kind = zzxxmla1_cl_bw_auth=>c_kind-node
                                                       value = `GP` hienm = 'ZCLDOC_ORG' version = '001'
                                                       node_iobjnm = '0HIER_NODE' named = abap_true ).
    DATA(request) = zzxxmla1_cl_bw_auth_sql=>request(
      characteristics = VALUE #( ( c_diag ) ( c_doc ) )
      factors         = VALUE #( ( slicer ) )
      members         = VALUE #( ( node ) ( value( `001` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( request-members ) ).
    " 001 is shown: in the product, also though it is named too
    cl_abap_unit_assert=>assert_equals( exp = 2 act = request-members[ 1 ]-pos ).
    " GP is only named (the node of a Children): checked alone
    cl_abap_unit_assert=>assert_equals( exp = node act = request-members[ 2 ]-member ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = request-members[ 2 ]-pos ).
    " ZCLDIAG has no member in the product: its aggregate
    cl_abap_unit_assert=>assert_equals(
      exp = VALUE zzxxmla1_cl_bw_auth=>ty_member( iobjnm = c_diag kind = zzxxmla1_cl_bw_auth=>c_kind-aggregate )
      act = request-members[ 3 ]-member ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = request-members[ 3 ]-pos ).
  ENDMETHOD.

  METHOD empty_factor.
    DATA(request) = zzxxmla1_cl_bw_auth_sql=>request(
      characteristics = VALUE #( ( c_diag ) ( c_doc ) )
      factors         = VALUE #( ( VALUE #( ( VALUE #( ( value( `001` ) ) ) ) ) ) ( VALUE #( ) ) ) ).
    cl_abap_unit_assert=>assert_false( request-product ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( request-members ) ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = request-members[ 1 ]-pos ).
  ENDMETHOD.

  METHOD statement_shape.
    DATA(request) = zzxxmla1_cl_bw_auth_sql=>request(
      characteristics = VALUE #( ( c_diag ) ( c_doc ) )
      factors         = VALUE #( ( VALUE #( ( VALUE #( ( value( `001` ) ) ) ) ( VALUE #( ( value( `002` ) ) ) ) ) )
                                 ( VALUE #( ( VALUE #( ( value( iobjnm = c_diag value = `I10` named = abap_true ) ) ) ) ) ) ) ).
    DATA(statement) = zzxxmla1_cl_bw_auth_sql=>check_statement( profile = profile( ) request = request ).
    DATA(sql) = statement-sql.
    " the sections in their order
    cl_abap_unit_assert=>assert_char_cp(
      act = sql
      exp = `WITH*request_members AS (*auth_parts AS (*auth_ranges AS (*auth_lines AS (*copies AS (*copy_paths AS (*` &&
            `copy_unassigned AS (*line_reach AS (*line_members AS (*range_matches AS (*value_admissions AS (*` &&
            `node_admissions AS (*flag_admissions AS (*member_admissions AS (*member_masks AS (*member_classes AS (*` &&
            `characteristics_with_values AS (*hierarchies_with_lines AS (*refused_members AS (*` &&
            `ORDER BY ROW_TYPE, POS, M` ).
    cl_abap_unit_assert=>assert_char_cp( act = sql exp = `*    M INTEGER PATH '$.M',*` ).
    " a branch per hierarchy characteristic of the provider, by its basic characteristic, no copy as literal
    cl_abap_unit_assert=>assert_char_cp( act = sql exp = `*JOIN "ZZXXMLA1P0000003" AS p *WHERE c.BASIC = 'ZCLDIAG'*` ).
    cl_abap_unit_assert=>assert_char_cp( act = sql exp = `*JOIN "ZZXXMLA1P0000002" AS p *WHERE c.BASIC = 'ZCLDOC'*` ).
    cl_abap_unit_assert=>assert_char_cp( act = sql exp = `*JOIN "/BIC/SZCLDOC" AS s ON s.SID = r.SID*` ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = count( val = sql sub = `41` ) ).
    " one JSON parameter per input, and the switch of the members' rows
    cl_abap_unit_assert=>assert_equals( exp = 6 act = lines( statement-params ) ).
    cl_abap_unit_assert=>assert_equals( exp = 6 act = count( val = sql sub = `?` ) ).
    " the three members 001, 002 and I10, and the two copies of the line on ZCLDOC
    DATA(members) = CAST string( statement-params[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = count( val = members->* sub = `"M":` ) ).
    DATA(copies) = CAST string( statement-params[ 5 ] ).
    cl_abap_unit_assert=>assert_char_cp(
      act = copies->*
      exp = `[{"IOBJ":"ZCLDOC","BASIC":"ZCLDOC","HIESID":41,*},{"IOBJ":"ZCLDOC","BASIC":"ZCLDOC","HIESID":40,*}]` ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = CAST i( statement-params[ 6 ] )->* ).
    DATA(listed) = zzxxmla1_cl_bw_auth_sql=>check_statement( profile = profile( ) request = request list_members = abap_true ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = CAST i( listed-params[ 6 ] )->* ).
  ENDMETHOD.

  METHOD same_text.
    DATA(small) = zzxxmla1_cl_bw_auth_sql=>check_statement(
      profile = profile( )
      request = zzxxmla1_cl_bw_auth_sql=>request( characteristics = VALUE #( ( c_diag ) ( c_doc ) )
                                                  members         = VALUE #( ( value( `001` ) ) ) ) ).
    DATA(other) = profile( ).
    APPEND VALUE #( auth = 'ZB' iobjnm = c_doc ranges = VALUE #( ( sign = 'I' option = 'BT' low = `001` high = `009` ) ) )
      TO other-flats.
    APPEND VALUE #( line     = VALUE #( auth = 'ZB' iobjnm = c_diag hienm = 'ZCLDIAG_ICD' node_iobjnm = '0HIER_NODE'
                                        node = `CARD` type = '3' date = '99991231' )
                    key_copy = VALUE #( basic = c_diag hiesid = 33 sver = `1` rest_shown = abap_true rest_top_sid = -39 ) )
      TO other-lines.
    DATA(large) = zzxxmla1_cl_bw_auth_sql=>check_statement(
      profile = other
      request = zzxxmla1_cl_bw_auth_sql=>request(
        characteristics = VALUE #( ( c_diag ) ( c_doc ) )
        factors         = VALUE #( ( VALUE #( ( VALUE #( ( value( `001` ) ) ) ) ( VALUE #( ( value( `002` ) ) ) ) ) )
                                   ( VALUE #( ( VALUE #( ( value( iobjnm = c_diag value = `I10` ) ) ) ) ) )
                                   ( VALUE #( ( VALUE #( ( value( `003` ) ) ) ) ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = small-sql act = large-sql ).
    cl_abap_unit_assert=>assert_differs( exp = CAST string( small-params[ 1 ] )->*
                                         act = CAST string( large-params[ 1 ] )->* ).
  ENDMETHOD.

  METHOD no_hierarchy_tables.
    DATA(profile) = VALUE zzxxmla1_cl_bw_auth_sql=>ty_profile(
      characteristics = VALUE #( ( c_doc ) )
      flats           = VALUE #( ( auth = 'ZA' iobjnm = c_doc ranges = VALUE #( ( sign = 'I' option = 'EQ' low = `002` ) ) ) ) ).
    DATA(sql) = zzxxmla1_cl_bw_auth_sql=>check_statement(
      profile = profile
      request = zzxxmla1_cl_bw_auth_sql=>request( characteristics = VALUE #( ( c_doc ) )
                                                  members         = VALUE #( ( value( `001` ) ) ) ) )-sql.
    cl_abap_unit_assert=>assert_char_cp( act = sql exp = `*copy_paths AS (*FROM copies AS c*WHERE 1 = 0 ),*` ).
    cl_abap_unit_assert=>assert_char_cp( act = sql exp = `*copy_unassigned AS (*WHERE c.REST_SHOWN = 1 ),*` ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = count( val = sql sub = `ZZXXMLA1P` ) ).
  ENDMETHOD.

  METHOD answers.
    DATA(request) = zzxxmla1_cl_bw_auth_sql=>request(
      characteristics = VALUE #( ( c_diag ) ( c_doc ) )
      factors         = VALUE #( ( VALUE #( ( VALUE #( ( value( value = `099` named = abap_true ) ) ) ) ) ) )
      members         = VALUE #( ( iobjnm = c_doc kind = zzxxmla1_cl_bw_auth=>c_kind-node value = `GP`
                                   hienm = 'ZCLDOC_ORG' version = '001' node_iobjnm = '0HIER_NODE' ) ) ).
    " members: 1 099 (ZCLDOC, pos 2), 2 GP (alone), 3 ZCLDIAG's aggregate (pos 1)
    cl_abap_unit_assert=>assert_equals(
      exp = zzxxmla1_cl_bw_auth=>c_status-allowed
      act = zzxxmla1_cl_bw_auth_sql=>answer( rows = VALUE #( ) request = request )-status ).
    " the named value before the node, the aggregate last
    DATA(unknown) = zzxxmla1_cl_bw_auth_sql=>answer(
      rows    = VALUE #( ( row( type = `REFUSED` pos = 1 m = 3 reason = `COMBINATION` ) )
                         ( row( type = `REFUSED` m = 2 reason = `NODE` ) )
                         ( row( type = `REFUSED` pos = 2 m = 1 reason = `VALUE` ) ) )
      request = request ).
    cl_abap_unit_assert=>assert_equals( exp = zzxxmla1_cl_bw_auth=>c_status-unknown act = unknown-status ).
    cl_abap_unit_assert=>assert_equals( exp = `Value 099 for characteristic ZCLDOC unknown` act = unknown-message ).
    DATA(node) = zzxxmla1_cl_bw_auth_sql=>answer(
      rows    = VALUE #( ( row( type = `REFUSED` pos = 1 m = 3 reason = `COMBINATION` ) )
                         ( row( type = `REFUSED` m = 2 reason = `NODE` ) ) )
      request = request ).
    cl_abap_unit_assert=>assert_equals( exp = `Hierarchy node GP of ZCLDOC_ORG version 001 not authorized`
                                        act = node-message ).
    DATA(aggregate) = zzxxmla1_cl_bw_auth_sql=>answer(
      rows    = VALUE #( ( row( type = `REFUSED` pos = 1 m = 3 reason = `COMBINATION` ) ) )
      request = request ).
    cl_abap_unit_assert=>assert_equals( exp = zzxxmla1_cl_bw_auth=>c_reason-combination act = aggregate-reason ).
    cl_abap_unit_assert=>assert_equals( exp = `You do not have sufficient authorization` act = aggregate-message ).
    " CROSS: two classes per characteristic, the cross combinations without a common bit
    DATA(cross) = zzxxmla1_cl_bw_auth_sql=>answer(
      rows    = VALUE #( ( row( type = `CLASS` pos = 1 mask = 1 m = 3 ) ) ( row( type = `CLASS` pos = 1 mask = 2 m = 3 ) )
                         ( row( type = `CLASS` pos = 2 mask = 1 m = 1 ) ) ( row( type = `CLASS` pos = 2 mask = 2 m = 1 ) ) )
      request = request ).
    cl_abap_unit_assert=>assert_equals( exp = zzxxmla1_cl_bw_auth=>c_reason-combination act = cross-reason ).
    DATA(covered) = zzxxmla1_cl_bw_auth_sql=>answer(
      rows    = VALUE #( ( row( type = `CLASS` pos = 1 mask = 3 m = 3 ) ) ( row( type = `CLASS` pos = 2 mask = 1 m = 1 ) )
                         ( row( type = `CLASS` pos = 2 mask = 2 m = 1 ) ) )
      request = request ).
    cl_abap_unit_assert=>assert_equals( exp = zzxxmla1_cl_bw_auth=>c_status-allowed act = covered-status ).
    " without a product an aggregate does not count, nor do classes
    DATA(alone) = zzxxmla1_cl_bw_auth_sql=>request(
      characteristics = VALUE #( ( c_diag ) ( c_doc ) )
      members         = VALUE #( ( iobjnm = c_diag kind = zzxxmla1_cl_bw_auth=>c_kind-aggregate ) ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = zzxxmla1_cl_bw_auth=>c_status-allowed
      act = zzxxmla1_cl_bw_auth_sql=>answer( rows    = VALUE #( ( row( type = `REFUSED` m = 1 reason = `COMBINATION` ) ) )
                                             request = alone )-status ).
  ENDMETHOD.

  METHOD holes.
    DATA(one) = CONV zzxxmla1_cl_bw_auth_sql=>ty_mask( 1 ).
    DATA(two) = CONV zzxxmla1_cl_bw_auth_sql=>ty_mask( 2 ).
    DATA(both) = CONV zzxxmla1_cl_bw_auth_sql=>ty_mask( 3 ).
    " two authorizations that cover only together: (1, 2) has no common bit
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_bw_auth_sql=>hole(
      dimensions = VALUE #( ( VALUE #( ( one ) ( two ) ) ) ( VALUE #( ( one ) ( two ) ) ) )
      depth      = 1
      mask       = zzxxmla1_cl_bw_auth_sql=>c_every ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_auth_sql=>hole(
      dimensions = VALUE #( ( VALUE #( ( both ) ) ) ( VALUE #( ( one ) ( two ) ) ) ( VALUE #( ( both ) ) ) )
      depth      = 1
      mask       = zzxxmla1_cl_bw_auth_sql=>c_every ) ).
    " a hole only at the third characteristic
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_bw_auth_sql=>hole(
      dimensions = VALUE #( ( VALUE #( ( both ) ) ) ( VALUE #( ( one ) ) ) ( VALUE #( ( both ) ( two ) ) ) )
      depth      = 1
      mask       = zzxxmla1_cl_bw_auth_sql=>c_every ) ).
  ENDMETHOD.

  METHOD values_as_json.
    DATA(columns) = VALUE zzxxmla1_cl_bw_auth_sql=>ty_columns( ( name = `M` type = `INTEGER` )
                                                               ( name = `MEMBER_KEY` type = `NVARCHAR(250)` ) ).
    DATA params TYPE zzxxmla1_cl_sql=>ty_t_param.
    DATA(one) = zzxxmla1_cl_bw_auth_sql=>values_sql(
      EXPORTING columns = columns
                rows    = VALUE #( ( VALUE #( ( NEW i( 7 ) ) ( NEW string( `a"b\c` ) ) ) ) )
      CHANGING  params  = params ).
    cl_abap_unit_assert=>assert_equals(
      act = one
      exp = |  SELECT * FROM JSON_TABLE( CAST( ? AS NCLOB ), '$[*]' COLUMNS (\n| &&
            |    M INTEGER PATH '$.M',\n| &&
            |    MEMBER_KEY NVARCHAR(250) PATH '$.MEMBER_KEY' ) ) AS j| ).
    cl_abap_unit_assert=>assert_equals( act = CAST string( params[ 1 ] )->* exp = `[{"M":7,"MEMBER_KEY":"a\"b\\c"}]` ).
    DATA(three) = zzxxmla1_cl_bw_auth_sql=>values_sql(
      EXPORTING columns = columns
                rows    = VALUE #( ( VALUE #( ( NEW i( 1 ) ) ( NEW string( `x` ) ) ) )
                                   ( VALUE #( ( NEW i( 2 ) ) ( NEW string( `y` ) ) ) )
                                   ( VALUE #( ( NEW int8( 3 ) ) ( NEW string( `` ) ) ) ) )
      CHANGING  params  = params ).
    DATA(none) = zzxxmla1_cl_bw_auth_sql=>values_sql( EXPORTING columns = columns rows = VALUE #( )
                                                      CHANGING  params  = params ).
    cl_abap_unit_assert=>assert_equals( act = three exp = one ).
    cl_abap_unit_assert=>assert_equals( act = none exp = one ).
    cl_abap_unit_assert=>assert_char_cp( act = CAST string( params[ 2 ] )->* exp = `*{"M":3,"MEMBER_KEY":""}]` ).
    cl_abap_unit_assert=>assert_equals( act = CAST string( params[ 3 ] )->* exp = `[]` ).
  ENDMETHOD.

ENDCLASS.
