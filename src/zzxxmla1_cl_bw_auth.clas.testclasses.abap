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
CLASS ltc_bw_auth DEFINITION DEFERRED.
CLASS zzxxmla1_cl_bw_auth DEFINITION LOCAL FRIENDS ltc_bw_auth.

"! The region and the check on made-up lines shaped as the clinic demo's scenarios (docs/clinic-demo.md,
"! Authorization scenarios): ZCLDOC with the 2025 slice of ZCLDOC_ORG 001, ZCLDIAG with a small ZCLDIAG_ICD.
CLASS ltc_bw_auth DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    TYPES ty_auth TYPE zzxxmla1_cl_bw_auth=>ty_lines.
    CONSTANTS c_doc TYPE rsiobjnm VALUE 'ZCLDOC'.
    CONSTANTS c_diag TYPE rsiobjnm VALUE 'ZCLDIAG'.
    CONSTANTS c_org TYPE rshienm VALUE 'ZCLDOC_ORG'.
    CONSTANTS c_icd TYPE rshienm VALUE 'ZCLDIAG_ICD'.

    METHODS full FOR TESTING.
    METHODS none FOR TESTING.
    METHODS other_provider FOR TESTING.
    METHODS missing_characteristic FOR TESTING.
    METHODS flat_values FOR TESTING.
    METHODS flat_aggregated FOR TESTING.
    METHODS interval_and_pattern FOR TESTING.
    METHODS not_assigned FOR TESTING.
    METHODS aggregate_only FOR TESTING.
    METHODS node_only FOR TESTING.
    METHODS subtree FOR TESTING.
    METHODS to_level FOR TESTING.
    METHODS complete FOR TESTING.
    METHODS other_version FOR TESTING.
    METHODS node_not_in_slice FOR TESTING.
    METHODS two_characteristics FOR TESTING.
    METHODS crossing FOR TESTING.
    METHODS variable FOR TESTING.
    METHODS links_and_intervals FOR TESTING.
    METHODS ranges FOR TESTING.

    "! the region of authorizations ZA, ZB, ... of the user: the special lines added to each
    METHODS region
      IMPORTING !values       TYPE zzxxmla1_cl_bw_auth=>ty_value_lines OPTIONAL
                hierarchies   TYPE zzxxmla1_cl_bw_auth=>ty_hierarchy_lines OPTIONAL
                auths         TYPE zzxxmla1_cl_bw_auth=>ty_auths OPTIONAL
                iprov         TYPE string DEFAULT `ZCLVISIT*`
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_bw_auth.
    METHODS value_line
      IMPORTING auth          TYPE rsauth DEFAULT 'ZA'
                iobjnm        TYPE rsiobjnm DEFAULT c_doc
                option        TYPE csequence DEFAULT 'EQ'
                low           TYPE csequence
                high          TYPE csequence OPTIONAL
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_value_line.
    METHODS hierarchy_line
      IMPORTING auth          TYPE rsauth DEFAULT 'ZA'
                iobjnm        TYPE rsiobjnm DEFAULT c_doc
                hienm         TYPE rshienm DEFAULT c_org
                version       TYPE rsversion DEFAULT '001'
                node_iobjnm   TYPE rsiobjnm DEFAULT zzxxmla1_cl_bw_auth=>c_text_node
                node          TYPE csequence
                type          TYPE csequence DEFAULT '1'
                level         TYPE i DEFAULT 0
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_hierarchy_line.
    "! ZCLDIAG CP * in ZA
    METHODS all_diagnoses
      IMPORTING auth          TYPE rsauth DEFAULT 'ZA'
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_value_line.
    METHODS org_slice RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_slice.
    METHODS icd_slice RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_slice.
    METHODS node
      IMPORTING id            TYPE i
                parent        TYPE i
                iobjnm        TYPE rsiobjnm DEFAULT zzxxmla1_cl_bw_auth=>c_text_node
                name          TYPE csequence
                level         TYPE i
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_node.

    "! a value of the physician as a tuple of its own (the diagnosis aggregated)
    METHODS doc
      IMPORTING !value        TYPE csequence
                named         TYPE abap_bool DEFAULT abap_true
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_member.
    METHODS diag
      IMPORTING !value        TYPE csequence
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_member.
    "! a node of ZCLDOC_ORG (a text node, or a leaf with iobjnm ZCLDOC)
    METHODS org
      IMPORTING !name         TYPE csequence
                iobjnm        TYPE rsiobjnm DEFAULT zzxxmla1_cl_bw_auth=>c_text_node
                version       TYPE rsversion DEFAULT '001'
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_member.
    METHODS icd
      IMPORTING !name         TYPE csequence
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_member.
    "! the total: no characteristic named, both aggregated
    METHODS total RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_selection.
    "! [ZCLDOC].Members: the All member and every value, from a set
    METHODS doc_members RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_selection.
    METHODS assert_check
      IMPORTING region    TYPE REF TO zzxxmla1_cl_bw_auth
                selection TYPE zzxxmla1_cl_bw_auth=>ty_selection
                !status   TYPE csequence
                reason    TYPE csequence OPTIONAL
                msg       TYPE csequence.
ENDCLASS.


CLASS ltc_bw_auth IMPLEMENTATION.

  METHOD region.
    DATA lines TYPE zzxxmla1_cl_bw_auth=>ty_lines.
    lines = VALUE #( provider        = `ZCLVISITA`
                     today           = '20261024'
                     characteristics = VALUE #( ( c_diag ) ( c_doc ) )
                     specials        = VALUE #( ( '0TCAACTVT' ) ( '0TCAIPROV' ) ( '0TCAVALID' ) )
                     values          = values
                     hierarchies     = hierarchies
                     slices          = VALUE #( ( org_slice( ) ) ( icd_slice( ) ) ) ).
    lines-auths = auths.
    IF auths IS NOT SUPPLIED.
      LOOP AT values INTO DATA(v).
        APPEND v-auth TO lines-auths.
      ENDLOOP.
      LOOP AT hierarchies INTO DATA(h).
        APPEND h-auth TO lines-auths.
      ENDLOOP.
    ENDIF.
    DATA(names) = lines-auths.
    SORT names BY table_line.
    DELETE ADJACENT DUPLICATES FROM names COMPARING table_line.
    LOOP AT names INTO DATA(name).
      APPEND value_line( auth = name iobjnm = '0TCAIPROV' option = 'CP' low = iprov ) TO lines-values.
      APPEND value_line( auth = name iobjnm = '0TCAACTVT' low = `03` ) TO lines-values.
      APPEND value_line( auth = name iobjnm = '0TCAVALID' option = 'CP' low = `*` ) TO lines-values.
    ENDLOOP.
    result = zzxxmla1_cl_bw_auth=>create( lines ).
  ENDMETHOD.

  METHOD value_line.
    result = VALUE #( auth = auth iobjnm = iobjnm sign = 'I' option = option low = low high = high ).
  ENDMETHOD.

  METHOD hierarchy_line.
    result = VALUE #( auth = auth iobjnm = iobjnm hienm = hienm version = version node_iobjnm = node_iobjnm
                      node = node type = type level = level ).
  ENDMETHOD.

  METHOD all_diagnoses.
    result = value_line( auth = auth iobjnm = c_diag option = 'CP' low = `*` ).
  ENDMETHOD.

  METHOD node.
    result = VALUE #( nodeid = id parentid = parent iobjnm = iobjnm name = name level = level ).
  ENDMETHOD.

  METHOD org_slice.
    result = VALUE #( iobjnm = c_doc hienm = c_org version = '001' nodes = VALUE #(
      ( node( id = 1  parent = 0  name = `CLINIC`    level = 1 ) )
      ( node( id = 2  parent = 1  name = `PRIMARY`   level = 2 ) )
      ( node( id = 3  parent = 2  name = `GP`        level = 3 ) )
      ( node( id = 4  parent = 3  name = `001` iobjnm = c_doc level = 4 ) )
      ( node( id = 5  parent = 3  name = `002` iobjnm = c_doc level = 4 ) )
      ( node( id = 6  parent = 3  name = `003` iobjnm = c_doc level = 4 ) )
      ( node( id = 7  parent = 3  name = `004` iobjnm = c_doc level = 4 ) )
      ( node( id = 8  parent = 3  name = `005` iobjnm = c_doc level = 4 ) )
      ( node( id = 9  parent = 3  name = `008` iobjnm = c_doc level = 4 ) )
      ( node( id = 10 parent = 2  name = `PED`       level = 3 ) )
      ( node( id = 11 parent = 10 name = `006` iobjnm = c_doc level = 4 ) )
      ( node( id = 12 parent = 10 name = `007` iobjnm = c_doc level = 4 ) )
      ( node( id = 13 parent = 2  name = `DERM`      level = 3 ) )
      ( node( id = 14 parent = 13 name = `017` iobjnm = c_doc level = 4 ) )
      ( node( id = 15 parent = 13 name = `018` iobjnm = c_doc level = 4 ) )
      ( node( id = 16 parent = 1  name = `SPECIAL`   level = 2 ) )
      ( node( id = 17 parent = 16 name = `INTMED`    level = 3 ) )
      ( node( id = 18 parent = 17 name = `CARD`      level = 4 ) )
      ( node( id = 19 parent = 18 name = `009` iobjnm = c_doc level = 5 ) )
      ( node( id = 20 parent = 18 name = `010` iobjnm = c_doc level = 5 ) )
      ( node( id = 21 parent = 17 name = `PULM`      level = 4 ) )
      ( node( id = 22 parent = 21 name = `012` iobjnm = c_doc level = 5 ) )
      ( node( id = 23 parent = 21 name = `013` iobjnm = c_doc level = 5 ) )
      ( node( id = 24 parent = 16 name = `ORTH`      level = 3 ) )
      ( node( id = 25 parent = 24 name = `014` iobjnm = c_doc level = 4 ) )
      ( node( id = 26 parent = 24 name = `015` iobjnm = c_doc level = 4 ) )
      ( node( id = 27 parent = 24 name = `016` iobjnm = c_doc level = 4 ) )
      ( node( id = 28 parent = 1  name = `EMERGENCY` level = 2 ) )
      ( node( id = 29 parent = 28 name = `EMER`      level = 3 ) )
      ( node( id = 30 parent = 29 name = `011` iobjnm = c_doc level = 4 ) )
      ( node( id = 31 parent = 29 name = `019` iobjnm = c_doc level = 4 ) )
      ( node( id = 32 parent = 29 name = `020` iobjnm = c_doc level = 4 ) ) ) ).
  ENDMETHOD.

  METHOD icd_slice.
    result = VALUE #( iobjnm = c_diag hienm = c_icd nodes = VALUE #(
      ( node( id = 1 parent = 0 name = `DIAGNOSES`   level = 1 ) )
      ( node( id = 2 parent = 1 name = `CIRCULATORY` level = 2 ) )
      ( node( id = 3 parent = 2 name = `I10` iobjnm = c_diag level = 3 ) )
      ( node( id = 4 parent = 1 name = `RESPIRATORY` level = 2 ) )
      ( node( id = 5 parent = 4 name = `J45` iobjnm = c_diag level = 3 ) ) ) ).
  ENDMETHOD.

  METHOD doc.
    result = VALUE #( iobjnm = c_doc kind = zzxxmla1_cl_bw_auth=>c_kind-value value = value named = named ).
  ENDMETHOD.

  METHOD diag.
    result = VALUE #( iobjnm = c_diag kind = zzxxmla1_cl_bw_auth=>c_kind-value value = value named = abap_true ).
  ENDMETHOD.

  METHOD org.
    result = VALUE #( iobjnm = c_doc kind = zzxxmla1_cl_bw_auth=>c_kind-node value = name hienm = c_org
                      version = version node_iobjnm = iobjnm named = abap_true ).
  ENDMETHOD.

  METHOD icd.
    result = VALUE #( iobjnm = c_diag kind = zzxxmla1_cl_bw_auth=>c_kind-node value = name hienm = c_icd
                      node_iobjnm = zzxxmla1_cl_bw_auth=>c_text_node named = abap_true ).
  ENDMETHOD.

  METHOD total.
    result = VALUE #( ( VALUE #( ) ) ).
  ENDMETHOD.

  METHOD doc_members.
    result = VALUE #( ( VALUE #( ( iobjnm = c_doc kind = zzxxmla1_cl_bw_auth=>c_kind-aggregate ) ) ) ).
    DO 20 TIMES.
      APPEND VALUE #( ( doc( value = |{ sy-index WIDTH = 3 ALIGN = RIGHT PAD = '0' }| named = abap_false ) ) )
        TO result.
    ENDDO.
  ENDMETHOD.

  METHOD assert_check.
    DATA(check) = region->check( selection ).
    cl_abap_unit_assert=>assert_equals( act = check-status exp = status msg = |{ msg }: { check-message }| ).
    IF reason IS SUPPLIED.
      cl_abap_unit_assert=>assert_equals( act = check-reason exp = reason msg = |{ msg }: { check-message }| ).
    ENDIF.
  ENDMETHOD.

  METHOD full.
    DATA(region) = region( values = VALUE #( ( value_line( option = 'CP' low = `*` ) ) ( all_diagnoses( ) ) ) ).
    cl_abap_unit_assert=>assert_true( region->unrestricted( ) ).
    assert_check( region = region selection = total( ) status = zzxxmla1_cl_bw_auth=>c_status-allowed msg = `total` ).
    assert_check( region = region selection = doc_members( ) status = zzxxmla1_cl_bw_auth=>c_status-allowed
                  msg = `members` ).
    DATA(access) = region->hierarchy_access( iobjnm = c_doc hienm = c_org version = '001' ).
    cl_abap_unit_assert=>assert_true( access-all ).
  ENDMETHOD.

  METHOD none.
    DATA(region) = region( ).
    assert_check( region = region selection = total( ) status = zzxxmla1_cl_bw_auth=>c_status-no_auth
                  reason = zzxxmla1_cl_bw_auth=>c_reason-provider msg = `total` ).
    cl_abap_unit_assert=>assert_initial( region->applying( ) ).
  ENDMETHOD.

  METHOD other_provider.
    DATA(region) = region( values = VALUE #( ( value_line( option = 'CP' low = `*` ) ) ( all_diagnoses( ) ) )
                           iprov  = `ZOTHER` ).
    assert_check( region = region selection = total( ) status = zzxxmla1_cl_bw_auth=>c_status-no_auth
                  reason = zzxxmla1_cl_bw_auth=>c_reason-provider msg = `other provider` ).
  ENDMETHOD.

  METHOD missing_characteristic.
    " no line for the diagnosis: the authorization does not apply
    DATA(region) = region( values = VALUE #( ( value_line( option = 'CP' low = `*` ) ) ) ).
    assert_check( region = region selection = total( ) status = zzxxmla1_cl_bw_auth=>c_status-no_auth
                  reason = zzxxmla1_cl_bw_auth=>c_reason-provider msg = `no ZCLDIAG line` ).
  ENDMETHOD.

  METHOD flat_values.
    DATA(region) = region( values = VALUE #( ( value_line( low = `001` ) ) ( value_line( low = `008` ) )
                                             ( value_line( low = `012` ) ) ( all_diagnoses( ) ) ) ).
    cl_abap_unit_assert=>assert_false( region->unrestricted( ) ).
    assert_check( region = region selection = total( ) status = zzxxmla1_cl_bw_auth=>c_status-no_auth
                  reason = zzxxmla1_cl_bw_auth=>c_reason-combination msg = `total without :` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `001` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-allowed msg = `001` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `002` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-unknown reason = zzxxmla1_cl_bw_auth=>c_reason-value
                  msg = `002` ).
    assert_check( region = region selection = doc_members( ) status = zzxxmla1_cl_bw_auth=>c_status-no_auth
                  reason = zzxxmla1_cl_bw_auth=>c_reason-combination msg = `members` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( org( name = `001` iobjnm = c_doc ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-no_auth reason = zzxxmla1_cl_bw_auth=>c_reason-hierarchy
                  msg = `a leaf of a hierarchy without a line` ).
    cl_abap_unit_assert=>assert_initial( region->hierarchy_access( iobjnm = c_doc hienm = c_org version = '001' ) ).
  ENDMETHOD.

  METHOD flat_aggregated.
    DATA(region) = region( values = VALUE #( ( value_line( low = `001` ) ) ( value_line( low = `008` ) )
                                             ( value_line( low = `:` ) ) ( all_diagnoses( ) ) ) ).
    assert_check( region = region selection = total( ) status = zzxxmla1_cl_bw_auth=>c_status-allowed
                  msg = `total with :` ).
    assert_check( region = region selection = doc_members( ) status = zzxxmla1_cl_bw_auth=>c_status-no_auth
                  msg = `members with :` ).
    " the values the user may see, each with the diagnosis aggregated, and on a value of it
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `001` ) ) ) ) ( VALUE #( ( doc( `008` ) ) ) )
                                                        ( VALUE #( ( doc( `008` ) ) ( diag( `J45` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-allowed msg = `001, 008` ).
  ENDMETHOD.

  METHOD interval_and_pattern.
    DATA(region) = region( values = VALUE #( ( value_line( option = 'BT' low = `001` high = `005` ) )
                                             ( value_line( auth = 'ZB' option = 'CP' low = `01*` ) )
                                             ( all_diagnoses( ) ) ( all_diagnoses( 'ZB' ) ) ) ).
    LOOP AT VALUE string_table( ( `001` ) ( `003` ) ( `005` ) ( `010` ) ( `015` ) ( `019` ) ) INTO DATA(allowed).
      assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( allowed ) ) ) ) )
                    status = zzxxmla1_cl_bw_auth=>c_status-allowed msg = allowed ).
    ENDLOOP.
    LOOP AT VALUE string_table( ( `006` ) ( `020` ) ( `#` ) ) INTO DATA(unknown).
      assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( unknown ) ) ) ) )
                    status = zzxxmla1_cl_bw_auth=>c_status-unknown msg = unknown ).
    ENDLOOP.
  ENDMETHOD.

  METHOD not_assigned.
    DATA(region) = region( values = VALUE #( ( value_line( low = `#` ) ) ( all_diagnoses( ) ) ) ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-allowed msg = `the initial value` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `#` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-allowed msg = `#` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `001` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-unknown msg = `001` ).
    assert_check( region = region selection = total( ) status = zzxxmla1_cl_bw_auth=>c_status-no_auth msg = `total` ).
  ENDMETHOD.

  METHOD aggregate_only.
    DATA(region) = region( values = VALUE #( ( value_line( low = `:` ) ) ( all_diagnoses( ) ) ) ).
    assert_check( region = region selection = total( ) status = zzxxmla1_cl_bw_auth=>c_status-allowed msg = `total` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `001` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-no_auth reason = zzxxmla1_cl_bw_auth=>c_reason-no_values
                  msg = `001` ).
    " a slicer on the diagnosis aggregates the physician
    assert_check( region = region selection = VALUE #( ( VALUE #( ( diag( `I10` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-allowed msg = `I10` ).
  ENDMETHOD.

  METHOD node_only.
    DATA(region) = region( values      = VALUE #( ( all_diagnoses( ) ) )
                           hierarchies = VALUE #( ( hierarchy_line( node = `GP` type = '0' ) ) ) ).
    DATA(access) = region->hierarchy_access( iobjnm = c_doc hienm = c_org version = '001' ).
    cl_abap_unit_assert=>assert_equals( act = lines( access-nodes ) exp = 1 ).
    DATA(gp) = access-nodes[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = gp-name exp = `GP` ).
    cl_abap_unit_assert=>assert_false( gp-expandable ).
    cl_abap_unit_assert=>assert_true( gp-top ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( org( `GP` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-allowed msg = `GP` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( org( `CLINIC` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-no_auth reason = zzxxmla1_cl_bw_auth=>c_reason-node
                  msg = `CLINIC` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `001` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-no_auth reason = zzxxmla1_cl_bw_auth=>c_reason-no_values
                  msg = `001` ).
  ENDMETHOD.

  METHOD subtree.
    DATA(region) = region( values      = VALUE #( ( all_diagnoses( ) ) )
                           hierarchies = VALUE #( ( hierarchy_line( node = `GP` ) ) ) ).
    DATA(access) = region->hierarchy_access( iobjnm = c_doc hienm = c_org version = '001' ).
    cl_abap_unit_assert=>assert_false( access-all ).
    cl_abap_unit_assert=>assert_equals( act = lines( access-nodes ) exp = 7 msg = `GP and its six physicians` ).
    DATA(gp) = access-nodes[ iobjnm = zzxxmla1_cl_bw_auth=>c_text_node name = `GP` ].
    cl_abap_unit_assert=>assert_true( gp-top ).
    cl_abap_unit_assert=>assert_true( gp-expandable ).
    DATA(leaf) = access-nodes[ iobjnm = c_doc name = `008` ].
    cl_abap_unit_assert=>assert_false( leaf-top ).
    cl_abap_unit_assert=>assert_equals( act = leaf-parent_name exp = `GP` ).
    cl_abap_unit_assert=>assert_equals( act = leaf-level exp = 4 ).
    " the leaves are flat values too
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `008` ) ) ( diag( `I10` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-allowed msg = `008` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `006` ) ) ( diag( `I10` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-unknown msg = `006` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( org( `PRIMARY` ) ) ( diag( `I10` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-no_auth reason = zzxxmla1_cl_bw_auth=>c_reason-node
                  msg = `the parent of GP` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( org( `GP` ) ) ( diag( `I10` ) ) ) )
                                                        ( VALUE #( ( org( name = `001` iobjnm = c_doc ) )
                                                                   ( diag( `I10` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-allowed msg = `GP and a leaf` ).
    assert_check( region = region selection = total( ) status = zzxxmla1_cl_bw_auth=>c_status-no_auth msg = `total` ).
  ENDMETHOD.

  METHOD to_level.
    DATA(region) = region( values      = VALUE #( ( all_diagnoses( ) ) )
                           hierarchies = VALUE #( ( hierarchy_line( node = `SPECIAL` type = '2' level = 3 ) ) ) ).
    DATA(access) = region->hierarchy_access( iobjnm = c_doc hienm = c_org version = '001' ).
    cl_abap_unit_assert=>assert_equals( act = lines( access-nodes ) exp = 3 msg = `SPECIAL, INTMED, ORTH` ).
    cl_abap_unit_assert=>assert_true( access-nodes[ name = `SPECIAL` ]-expandable ).
    cl_abap_unit_assert=>assert_false( access-nodes[ name = `INTMED` ]-expandable ).
    cl_abap_unit_assert=>assert_false( access-nodes[ name = `ORTH` ]-expandable ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( org( `CARD` ) ) ( diag( `I10` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-no_auth reason = zzxxmla1_cl_bw_auth=>c_reason-node
                  msg = `CARD, below the level` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `009` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-no_auth reason = zzxxmla1_cl_bw_auth=>c_reason-no_values
                  msg = `no leaf, no value` ).
  ENDMETHOD.

  METHOD complete.
    DATA(region) = region( values      = VALUE #( ( all_diagnoses( ) ) )
                           hierarchies = VALUE #( ( hierarchy_line( node = `CLINIC` type = '3' ) ) ) ).
    DATA(access) = region->hierarchy_access( iobjnm = c_doc hienm = c_org version = '001' ).
    cl_abap_unit_assert=>assert_equals( act = lines( access-nodes ) exp = 32 ).
    cl_abap_unit_assert=>assert_true( access-nodes[ name = `CLINIC` ]-top ).
    cl_abap_unit_assert=>assert_equals( act = lines( FILTER #( access-nodes USING KEY primary_key
                                                               WHERE iobjnm = zzxxmla1_cl_bw_auth=>c_text_node ) )
                                        exp = 12 ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `020` ) ) ( diag( `J45` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-allowed msg = `020` ).
    assert_check( region = region selection = total( ) status = zzxxmla1_cl_bw_auth=>c_status-no_auth
                  msg = `the complete hierarchy is no aggregate` ).
  ENDMETHOD.

  METHOD other_version.
    DATA(region) = region( values      = VALUE #( ( all_diagnoses( ) ) )
                           hierarchies = VALUE #( ( hierarchy_line( node = `GP` version = '002' ) ) ) ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( org( `GP` ) ) ( diag( `I10` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-no_auth reason = zzxxmla1_cl_bw_auth=>c_reason-hierarchy
                  msg = `GP of version 001` ).
    cl_abap_unit_assert=>assert_initial( region->hierarchy_access( iobjnm = c_doc hienm = c_org version = '001' ) ).
  ENDMETHOD.

  METHOD node_not_in_slice.
    " a leaf the slice at the key date does not have: the line shows nothing
    DATA(region) = region( values      = VALUE #( ( all_diagnoses( ) ) )
                           hierarchies = VALUE #( ( hierarchy_line( node_iobjnm = c_doc node = `099` type = '0' ) ) ) ).
    cl_abap_unit_assert=>assert_initial(
      region->hierarchy_access( iobjnm = c_doc hienm = c_org version = '001' )-nodes ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `099` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-no_auth reason = zzxxmla1_cl_bw_auth=>c_reason-no_values
                  msg = `099` ).
    " a leaf as type 0 is the value
    region = region( values      = VALUE #( ( all_diagnoses( ) ) )
                     hierarchies = VALUE #( ( hierarchy_line( node_iobjnm = c_doc node = `008` type = '0' ) ) ) ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `008` ) ) ( diag( `I10` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-allowed msg = `008` ).
  ENDMETHOD.

  METHOD two_characteristics.
    DATA(region) = region( hierarchies = VALUE #( ( hierarchy_line( node = `PULM` ) )
                                                  ( hierarchy_line( iobjnm = c_diag hienm = c_icd version = ''
                                                                    node = `RESPIRATORY` ) ) ) ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( org( `PULM` ) ) ( icd( `RESPIRATORY` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-allowed msg = `PULM in RESPIRATORY` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `012` ) ) ( diag( `J45` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-allowed msg = `012 with J45` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( org( `PULM` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-no_auth reason = zzxxmla1_cl_bw_auth=>c_reason-combination
                  msg = `PULM, the diagnosis aggregated` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( org( `GP` ) ) ( icd( `RESPIRATORY` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-no_auth reason = zzxxmla1_cl_bw_auth=>c_reason-node
                  msg = `GP` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `001` ) ) ( diag( `J45` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-unknown msg = `001` ).
  ENDMETHOD.

  METHOD crossing.
    DATA(region) = region( values = VALUE #( ( value_line( auth = 'ZA' low = `009` ) )
                                             ( value_line( auth = 'ZA' iobjnm = c_diag low = `I10` ) )
                                             ( value_line( auth = 'ZB' low = `012` ) )
                                             ( value_line( auth = 'ZB' iobjnm = c_diag low = `J45` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( region->applying( ) ) exp = 2 ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `009` ) ) ( diag( `I10` ) ) ) )
                                                        ( VALUE #( ( doc( `012` ) ) ( diag( `J45` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-allowed msg = `the two pairs` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `009` ) ) ( diag( `J45` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-no_auth reason = zzxxmla1_cl_bw_auth=>c_reason-combination
                  msg = `009 with J45` ).
    assert_check( region = region selection = VALUE #( ( VALUE #( ( doc( `009` ) ) ) ) )
                  status = zzxxmla1_cl_bw_auth=>c_status-no_auth reason = zzxxmla1_cl_bw_auth=>c_reason-combination
                  msg = `009 alone` ).
  ENDMETHOD.

  METHOD variable.
    DATA(region) = region( values = VALUE #( ( value_line( option = 'CP' low = `*` ) ) ( all_diagnoses( ) )
                                             ( value_line( auth = 'ZB' low = `$ZVAR` ) )
                                             ( all_diagnoses( 'ZB' ) ) ) ).
    assert_check( region = region selection = total( ) status = zzxxmla1_cl_bw_auth=>c_status-no_auth
                  reason = zzxxmla1_cl_bw_auth=>c_reason-variable msg = `a variable` ).
    " of an authorization of another provider it does not matter
    DATA(lines) = VALUE zzxxmla1_cl_bw_auth=>ty_value_lines( ( value_line( option = 'CP' low = `*` ) )
                                                             ( all_diagnoses( ) ) ).
    region = region( values = lines ).
    DATA(other) = zzxxmla1_cl_bw_auth=>create( VALUE #(
      provider = `ZCLVISITA` today = '20261024' characteristics = VALUE #( ( c_diag ) ( c_doc ) )
      specials = VALUE #( ( '0TCAIPROV' ) ) auths = VALUE #( ( 'ZA' ) ( 'ZB' ) )
      values = VALUE #( BASE lines ( value_line( auth = 'ZA' iobjnm = '0TCAIPROV' option = 'CP' low = `*` ) )
                        ( value_line( auth = 'ZB' iobjnm = '0TCAIPROV' low = `ZOTHER` ) )
                        ( value_line( auth = 'ZB' low = `$ZVAR` ) ) ) ) ).
    assert_check( region = other selection = total( ) status = zzxxmla1_cl_bw_auth=>c_status-allowed
                  msg = `a variable of another provider` ).
    assert_check( region = region selection = total( ) status = zzxxmla1_cl_bw_auth=>c_status-allowed
                  msg = `no variable` ).
  ENDMETHOD.

  METHOD links_and_intervals.
    " ROOT > A > (x1, interval 100-199), ROOT > B > link A: the link shows A's children below B
    DATA(slice) = VALUE zzxxmla1_cl_bw_auth=>ty_slice( iobjnm = c_doc hienm = 'ZLINKS' nodes = VALUE #(
      ( node( id = 1 parent = 0 name = `ROOT` level = 1 ) )
      ( node( id = 2 parent = 1 name = `A` level = 2 ) )
      ( node( id = 3 parent = 2 name = `X1` iobjnm = c_doc level = 3 ) )
      ( VALUE #( nodeid = 4 parentid = 2 iobjnm = c_doc name = `I1` level = 3 interval = abap_true
                 low = `100` high = `199` ) )
      ( node( id = 5 parent = 1 name = `B` level = 2 ) )
      ( VALUE #( nodeid = 6 parentid = 5 iobjnm = zzxxmla1_cl_bw_auth=>c_text_node name = `A` level = 3
                 link = abap_true ) ) ) ).
    DATA(cover) = zzxxmla1_cl_bw_auth=>cover( line  = hierarchy_line( hienm = 'ZLINKS' node = `B` )
                                              slice = slice ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( cover-nodes[ name = `X1` ] ) ) ).
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_bw_auth=>in_ranges( value = `150` ranges = cover-ranges ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_auth=>in_ranges( value = `200` ranges = cover-ranges ) ).
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_bw_auth=>in_ranges( value = `X1` ranges = cover-ranges ) ).
  ENDMETHOD.

  METHOD ranges.
    DATA(r) = VALUE zzxxmla1_cl_bw_auth=>ty_ranges( ( sign = 'I' option = 'CP' low = `A+C*` )
                                                    ( sign = 'E' option = 'EQ' low = `ABCD` ) ).
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_bw_auth=>in_ranges( value = `ABC` ranges = r ) ).
    cl_abap_unit_assert=>assert_true( zzxxmla1_cl_bw_auth=>in_ranges( value = `AXCZZ` ranges = r ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_auth=>in_ranges( value = `ABCD` ranges = r ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_auth=>in_ranges( value = `abc` ranges = r ) ).
    cl_abap_unit_assert=>assert_false( zzxxmla1_cl_bw_auth=>in_ranges( value = `AXD` ranges = VALUE #(
                                                                           ( sign = 'I' option = 'CP' low = `A.D` ) ) ) ).
  ENDMETHOD.

ENDCLASS.
