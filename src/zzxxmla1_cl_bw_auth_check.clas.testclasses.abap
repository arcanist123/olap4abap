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
CLASS ltc_bw_auth_check DEFINITION DEFERRED.
CLASS zzxxmla1_cl_bw_auth_check DEFINITION LOCAL FRIENDS ltc_bw_auth_check.

"! The cover of the product by classes of masks and the request's form, on made-up masks; whether the API answers as
"! BW does is scripts/auth_check_test.py's (GET auth/check?engine=api against reference/auth/).
CLASS ltc_bw_auth_check DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    CONSTANTS c_doc TYPE rsiobjnm VALUE 'ZCLDOC'.
    CONSTANTS c_diag TYPE rsiobjnm VALUE 'ZCLDIAG'.

    "! every combination has a common authorization: allowed, no hole
    METHODS covered FOR TESTING.
    "! one combination of classes without a common authorization: one hole, its members the two classes'
    METHODS one_hole FOR TESTING.
    "! two authorizations that cover the product only together: no hole
    METHODS covered_together FOR TESTING.
    "! a member in no authorization: refused with its reason, the rest still searched for holes
    METHODS member_in_none FOR TESTING.
    "! refused members in the order the walk of the product meets them: the last characteristic fastest
    METHODS walk_order FOR TESTING.
    "! an aggregate refused before a member: the member names the status, as BW checks aggregates last
    METHODS member_before_aggregate FOR TESTING.
    "! a hole on the first characteristic covers every class below it: one hole, not one per class
    METHODS hole_cuts_below FOR TESTING.
    "! more holes than c_max_holes: the first ones and more_holes
    METHODS many_holes FOR TESTING.
    "! members grouped by characteristic, each once, # for a blank value, : for the aggregate, a leaf's InfoObject
    METHODS grouping FOR TESTING.
    "! a leaf is a node of the characteristic for the check in HANA, the aggregate without value
    METHODS internal_members FOR TESTING.
    "! a characteristic not asked, a kind not known, a node without hierarchy: errors
    METHODS request_errors FOR TESTING.

    METHODS value
      IMPORTING iobjnm        TYPE rsiobjnm
                !value        TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_if_bw_auth_check=>ty_member.
    "! a mask of the authorization numbers given
    METHODS mask
      IMPORTING bits          TYPE int4_table
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth_check=>ty_mask.
    METHODS entry
      IMPORTING iobjnm        TYPE rsiobjnm
                !value        TYPE string
                bits          TYPE int4_table
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth_check=>ty_entry.
ENDCLASS.


CLASS ltc_bw_auth_check IMPLEMENTATION.

  METHOD value.
    result = VALUE #( characteristic = iobjnm kind = zzxxmla1_if_bw_auth_check=>c_kind-value value = value ).
  ENDMETHOD.

  METHOD mask.
    LOOP AT bits INTO DATA(bit).
      SET BIT bit OF result.
    ENDLOOP.
  ENDMETHOD.

  METHOD entry.
    result = VALUE #( member = value( iobjnm = iobjnm value = value ) mask = mask( bits ) ).
    IF bits IS INITIAL.
      result-refusal = VALUE #( member = result-member status = zzxxmla1_if_bw_auth_check=>c_status-unknown
                                reason = 'VALUE' message = |Value { value } for characteristic { iobjnm } unknown| ).
    ENDIF.
  ENDMETHOD.

  METHOD covered.
    " doctor 001 in authorizations 1 and 2, 002 in 2; diagnosis I10 in 1 and 2, J45 in 2: every pair shares 2
    DATA(answer) = zzxxmla1_cl_bw_auth_check=>decide( VALUE #(
      ( characteristic = c_doc entries = VALUE #( ( entry( iobjnm = c_doc value = `001` bits = VALUE #( ( 1 ) ( 2 ) ) ) )
                                                  ( entry( iobjnm = c_doc value = `002` bits = VALUE #( ( 2 ) ) ) ) ) )
      ( characteristic = c_diag entries = VALUE #( ( entry( iobjnm = c_diag value = `I10` bits = VALUE #( ( 1 ) ( 2 ) ) ) )
                                                   ( entry( iobjnm = c_diag value = `J45` bits = VALUE #( ( 2 ) ) ) ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = answer-status exp = zzxxmla1_if_bw_auth_check=>c_status-allowed ).
    cl_abap_unit_assert=>assert_initial( answer-holes ).
    cl_abap_unit_assert=>assert_initial( answer-refused ).
    cl_abap_unit_assert=>assert_initial( answer-combination ).
  ENDMETHOD.

  METHOD one_hole.
    " CROSS: 009 with I10 (authorization 1), 012 with J45 (authorization 2): 009 with J45 and 012 with I10 are holes
    DATA(answer) = zzxxmla1_cl_bw_auth_check=>decide( VALUE #(
      ( characteristic = c_doc entries = VALUE #( ( entry( iobjnm = c_doc value = `009` bits = VALUE #( ( 1 ) ) ) )
                                                  ( entry( iobjnm = c_doc value = `012` bits = VALUE #( ( 2 ) ) ) ) ) )
      ( characteristic = c_diag entries = VALUE #( ( entry( iobjnm = c_diag value = `I10` bits = VALUE #( ( 1 ) ) ) ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = answer-status exp = zzxxmla1_if_bw_auth_check=>c_status-no_auth ).
    cl_abap_unit_assert=>assert_equals( act = answer-reason exp = 'COMBINATION' ).
    cl_abap_unit_assert=>assert_equals( act = answer-holes
                                        exp = VALUE zzxxmla1_if_bw_auth_check=>ty_products(
                                          ( VALUE #( ( value( iobjnm = c_doc value = `012` ) )
                                                     ( value( iobjnm = c_diag value = `I10` ) ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = answer-combination
                                        exp = VALUE zzxxmla1_if_bw_auth_check=>ty_members(
                                          ( value( iobjnm = c_doc value = `012` ) )
                                          ( value( iobjnm = c_diag value = `I10` ) ) ) ).
  ENDMETHOD.

  METHOD covered_together.
    " authorization 1: 001 and 002 with I10; authorization 2: 001 and 002 with J45; together the whole product
    DATA(answer) = zzxxmla1_cl_bw_auth_check=>decide( VALUE #(
      ( characteristic = c_doc entries = VALUE #( ( entry( iobjnm = c_doc value = `001` bits = VALUE #( ( 1 ) ( 2 ) ) ) )
                                                  ( entry( iobjnm = c_doc value = `002` bits = VALUE #( ( 1 ) ( 2 ) ) ) ) ) )
      ( characteristic = c_diag entries = VALUE #( ( entry( iobjnm = c_diag value = `I10` bits = VALUE #( ( 1 ) ) ) )
                                                   ( entry( iobjnm = c_diag value = `J45` bits = VALUE #( ( 2 ) ) ) ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = answer-status exp = zzxxmla1_if_bw_auth_check=>c_status-allowed ).
    cl_abap_unit_assert=>assert_initial( answer-holes ).
  ENDMETHOD.

  METHOD member_in_none.
    DATA(answer) = zzxxmla1_cl_bw_auth_check=>decide( VALUE #(
      ( characteristic = c_doc entries = VALUE #( ( entry( iobjnm = c_doc value = `001` bits = VALUE #( ( 1 ) ) ) )
                                                  ( entry( iobjnm = c_doc value = `099` bits = VALUE #( ) ) ) ) )
      ( characteristic = c_diag entries = VALUE #( ( entry( iobjnm = c_diag value = `I10` bits = VALUE #( ( 1 ) ) ) )
                                                   ( entry( iobjnm = c_diag value = `J45` bits = VALUE #( ( 2 ) ) ) ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = answer-status exp = zzxxmla1_if_bw_auth_check=>c_status-unknown ).
    cl_abap_unit_assert=>assert_equals( act = answer-reason exp = 'VALUE' ).
    cl_abap_unit_assert=>assert_equals( act = lines( answer-refused ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = answer-refused[ 1 ]-member exp = value( iobjnm = c_doc value = `099` ) ).
    " the refused member with the first member of the other characteristic
    cl_abap_unit_assert=>assert_equals( act = answer-combination
                                        exp = VALUE zzxxmla1_if_bw_auth_check=>ty_members(
                                          ( value( iobjnm = c_doc value = `099` ) )
                                          ( value( iobjnm = c_diag value = `I10` ) ) ) ).
    " 001 with J45 is a hole of the admitted members too
    cl_abap_unit_assert=>assert_equals( act = answer-holes
                                        exp = VALUE zzxxmla1_if_bw_auth_check=>ty_products(
                                          ( VALUE #( ( value( iobjnm = c_doc value = `001` ) )
                                                     ( value( iobjnm = c_diag value = `J45` ) ) ) ) ) ).
  ENDMETHOD.

  METHOD walk_order.
    " 002 is first in combination 2 (002, I10), J45 in combination 1 (001, J45): J45 is met first
    DATA(answer) = zzxxmla1_cl_bw_auth_check=>decide( VALUE #(
      ( characteristic = c_doc entries = VALUE #( ( entry( iobjnm = c_doc value = `001` bits = VALUE #( ( 1 ) ) ) )
                                                  ( entry( iobjnm = c_doc value = `002` bits = VALUE #( ) ) ) ) )
      ( characteristic = c_diag entries = VALUE #( ( entry( iobjnm = c_diag value = `I10` bits = VALUE #( ( 1 ) ) ) )
                                                   ( entry( iobjnm = c_diag value = `J45` bits = VALUE #( ) ) ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = VALUE zzxxmla1_if_bw_auth_check=>ty_members( FOR r IN answer-refused ( r-member ) )
      exp = VALUE zzxxmla1_if_bw_auth_check=>ty_members( ( value( iobjnm = c_diag value = `J45` ) )
                                                         ( value( iobjnm = c_doc value = `002` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = answer-combination
                                        exp = VALUE zzxxmla1_if_bw_auth_check=>ty_members(
                                          ( value( iobjnm = c_doc value = `001` ) )
                                          ( value( iobjnm = c_diag value = `J45` ) ) ) ).
  ENDMETHOD.

  METHOD member_before_aggregate.
    DATA(aggregate) = VALUE zzxxmla1_cl_bw_auth_check=>ty_entry(
      member  = VALUE #( characteristic = c_diag kind = 'A' value = `:` )
      refusal = VALUE #( member = VALUE #( characteristic = c_diag kind = 'A' value = `:` )
                         status = zzxxmla1_if_bw_auth_check=>c_status-no_auth reason = 'COMBINATION' ) ).
    DATA(node) = VALUE zzxxmla1_cl_bw_auth_check=>ty_entry(
      member  = VALUE #( characteristic = c_doc kind = 'N' value = `CARD` hierarchy = 'ZCLDOC_SITE' version = '001'
                         node_iobjnm = '0HIER_NODE' )
      refusal = VALUE #( member = VALUE #( characteristic = c_doc kind = 'N' value = `CARD` hierarchy = 'ZCLDOC_SITE'
                                           version = '001' node_iobjnm = '0HIER_NODE' )
                         status = zzxxmla1_if_bw_auth_check=>c_status-no_auth reason = 'HIERARCHY' ) ).
    DATA(answer) = zzxxmla1_cl_bw_auth_check=>decide( VALUE #( ( characteristic = c_diag entries = VALUE #( ( aggregate ) ) )
                                                               ( characteristic = c_doc entries = VALUE #( ( node ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = answer-reason exp = 'HIERARCHY' ).
    cl_abap_unit_assert=>assert_equals( act = lines( answer-refused ) exp = 2 ).
  ENDMETHOD.

  METHOD hole_cuts_below.
    " doctor 001 in authorization 1, 002 in 2; the diagnoses all in 1: 002 is a hole with every diagnosis
    DATA(answer) = zzxxmla1_cl_bw_auth_check=>decide( VALUE #(
      ( characteristic = c_doc entries = VALUE #( ( entry( iobjnm = c_doc value = `001` bits = VALUE #( ( 1 ) ) ) )
                                                  ( entry( iobjnm = c_doc value = `002` bits = VALUE #( ( 2 ) ) ) ) ) )
      ( characteristic = c_diag entries = VALUE #( ( entry( iobjnm = c_diag value = `I10` bits = VALUE #( ( 1 ) ) ) )
                                                   ( entry( iobjnm = c_diag value = `J45` bits = VALUE #( ( 1 ) ( 3 ) ) ) ) ) ) ) ).
    " 002 meets the class of I10 and the one of J45 apart: two holes, each 002 with its class
    cl_abap_unit_assert=>assert_equals( act = lines( answer-holes ) exp = 2 ).
    " with one class of diagnoses the hole is 002 with all of them
    answer = zzxxmla1_cl_bw_auth_check=>decide( VALUE #(
      ( characteristic = c_doc entries = VALUE #( ( entry( iobjnm = c_doc value = `001` bits = VALUE #( ( 1 ) ) ) )
                                                  ( entry( iobjnm = c_doc value = `002` bits = VALUE #( ( 2 ) ) ) ) ) )
      ( characteristic = c_diag entries = VALUE #( ( entry( iobjnm = c_diag value = `I10` bits = VALUE #( ( 1 ) ) ) )
                                                   ( entry( iobjnm = c_diag value = `J45` bits = VALUE #( ( 1 ) ) ) ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = answer-holes
                                        exp = VALUE zzxxmla1_if_bw_auth_check=>ty_products(
                                          ( VALUE #( ( value( iobjnm = c_doc value = `002` ) )
                                                     ( value( iobjnm = c_diag value = `I10` ) )
                                                     ( value( iobjnm = c_diag value = `J45` ) ) ) ) ) ).
  ENDMETHOD.

  METHOD many_holes.
    " 120 doctors each in an authorization of its own, one diagnosis in none of them but a 121st: 120 holes
    DATA doctors TYPE zzxxmla1_cl_bw_auth_check=>ty_entries.
    DO 120 TIMES.
      APPEND entry( iobjnm = c_doc value = |{ sy-index WIDTH = 3 ALIGN = RIGHT PAD = '0' }|
                    bits = VALUE #( ( ( sy-index - 1 ) MOD 60 + 1 ) ) ) TO doctors.
    ENDDO.
    DATA(answer) = zzxxmla1_cl_bw_auth_check=>decide( VALUE #(
      ( characteristic = c_doc entries = doctors )
      ( characteristic = c_diag entries = VALUE #( ( entry( iobjnm = c_diag value = `I10` bits = VALUE #( ( 63 ) ) ) ) ) ) ) ).
    " 60 classes of doctors, each a hole
    cl_abap_unit_assert=>assert_equals( act = lines( answer-holes ) exp = 60 ).
    cl_abap_unit_assert=>assert_false( answer-more_holes ).

    CLEAR doctors.
    DO 120 TIMES.
      DATA(bits) = VALUE int4_table( ).
      DATA(number) = sy-index.
      " a distinct mask per doctor: two bits of 1 to 16
      APPEND ( number - 1 ) MOD 16 + 1 TO bits.
      APPEND ( number - 1 ) DIV 16 + 17 TO bits.
      APPEND entry( iobjnm = c_doc value = |{ number WIDTH = 3 ALIGN = RIGHT PAD = '0' }| bits = bits ) TO doctors.
    ENDDO.
    answer = zzxxmla1_cl_bw_auth_check=>decide( VALUE #(
      ( characteristic = c_doc entries = doctors )
      ( characteristic = c_diag entries = VALUE #( ( entry( iobjnm = c_diag value = `I10` bits = VALUE #( ( 63 ) ) ) ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( answer-holes ) exp = zzxxmla1_if_bw_auth_check=>c_max_holes ).
    cl_abap_unit_assert=>assert_true( answer-more_holes ).
  ENDMETHOD.

  METHOD grouping.
    DATA(groups) = zzxxmla1_cl_bw_auth_check=>groups_of( VALUE #(
      ( characteristic = c_doc kind = 'v' value = `001` )
      ( characteristic = c_diag kind = 'A' )
      ( characteristic = c_doc kind = 'V' value = `001` )
      ( characteristic = c_doc kind = 'V' )
      ( characteristic = c_doc kind = 'V' value = `008` hierarchy = 'ZCLDOC_ORG' version = '001' )
      ( characteristic = c_doc kind = 'N' value = `CARD` hierarchy = 'ZCLDOC_ORG' version = '001'
        node_iobjnm = '0HIER_NODE' ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( groups ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = groups[ 1 ]-characteristic exp = c_doc ).
    cl_abap_unit_assert=>assert_equals(
      act = VALUE zzxxmla1_if_bw_auth_check=>ty_members( FOR e IN groups[ 1 ]-entries ( e-member ) )
      exp = VALUE zzxxmla1_if_bw_auth_check=>ty_members(
        ( characteristic = c_doc kind = 'V' value = `001` )
        ( characteristic = c_doc kind = 'V' value = `#` )
        ( characteristic = c_doc kind = 'V' value = `008` hierarchy = 'ZCLDOC_ORG' version = '001' node_iobjnm = c_doc )
        ( characteristic = c_doc kind = 'N' value = `CARD` hierarchy = 'ZCLDOC_ORG' version = '001'
          node_iobjnm = '0HIER_NODE' ) ) ).
    cl_abap_unit_assert=>assert_equals( act = groups[ 2 ]-entries[ 1 ]-member
                                        exp = VALUE zzxxmla1_if_bw_auth_check=>ty_member(
                                          characteristic = c_diag kind = 'A' value = `:` ) ).
  ENDMETHOD.

  METHOD internal_members.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_auth_check=>internal( VALUE #( characteristic = c_doc kind = 'V' value = `008`
                                                          hierarchy = 'ZCLDOC_ORG' version = '001' node_iobjnm = c_doc ) )
      exp = VALUE zzxxmla1_cl_bw_auth=>ty_member( iobjnm = c_doc kind = 'N' value = `008` hienm = 'ZCLDOC_ORG'
                                                  version = '001' node_iobjnm = c_doc named = abap_true ) ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_auth_check=>internal( VALUE #( characteristic = c_doc kind = 'A' value = `:` ) )
      exp = VALUE zzxxmla1_cl_bw_auth=>ty_member( iobjnm = c_doc kind = 'A' named = abap_true ) ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_auth_check=>internal( VALUE #( characteristic = c_doc kind = 'V' value = `#` ) )
      exp = VALUE zzxxmla1_cl_bw_auth=>ty_member( iobjnm = c_doc kind = 'V' value = `#` named = abap_true ) ).
  ENDMETHOD.

  METHOD request_errors.
    DATA(check) = NEW zzxxmla1_cl_bw_auth_check( ).
    check->relevant = VALUE #( ( c_doc ) ( c_diag ) ).
    DATA(answer) = check->request_error( zzxxmla1_cl_bw_auth_check=>groups_of( VALUE #(
      ( characteristic = c_doc kind = 'V' value = `001` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = answer-status exp = zzxxmla1_if_bw_auth_check=>c_status-error ).
    cl_abap_unit_assert=>assert_equals( act = answer-reason exp = zzxxmla1_if_bw_auth_check=>c_error-missing ).
    cl_abap_unit_assert=>assert_char_cp( act = answer-message exp = '*ZCLDIAG*' ).

    answer = check->request_error( zzxxmla1_cl_bw_auth_check=>groups_of( VALUE #(
      ( characteristic = c_doc kind = 'X' value = `001` ) ( characteristic = c_diag kind = 'A' ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = answer-reason exp = zzxxmla1_if_bw_auth_check=>c_error-request ).

    answer = check->request_error( zzxxmla1_cl_bw_auth_check=>groups_of( VALUE #(
      ( characteristic = c_doc kind = 'N' value = `CARD` ) ( characteristic = c_diag kind = 'A' ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = answer-reason exp = zzxxmla1_if_bw_auth_check=>c_error-request ).

    answer = check->request_error( zzxxmla1_cl_bw_auth_check=>groups_of( VALUE #(
      ( characteristic = c_doc kind = 'V' value = `001` ) ( characteristic = c_diag kind = 'A' )
      ( characteristic = '0CALMONTH' kind = 'V' value = `199701` ) ) ) ).
    cl_abap_unit_assert=>assert_initial( answer ).
  ENDMETHOD.

ENDCLASS.
