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
"! The probe's queries on made-up lines shaped as the scenarios H1 (the subtree of GP), H0 (the node GP only) and EQ
"! (flat values, no hierarchy line), on a small ZCLDOC_ORG 001 and ZCLDIAG_ICD; the answers as reference/auth/ has
"! BW's.
CLASS ltc_bw_auth_queries DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    CONSTANTS c_doc TYPE rsiobjnm VALUE 'ZCLDOC'.
    CONSTANTS c_diag TYPE rsiobjnm VALUE 'ZCLDIAG'.
    CONSTANTS c_org TYPE string VALUE `ZCLDOC_ORG 001`.

    METHODS subtree FOR TESTING.
    METHODS node_only FOR TESTING.
    METHODS flat_values FOR TESTING.

    "! the queries for the lines of authorization ZA (the special lines added)
    METHODS run
      IMPORTING !values       TYPE zzxxmla1_cl_bw_auth=>ty_value_lines OPTIONAL
                hierarchies   TYPE zzxxmla1_cl_bw_auth=>ty_hierarchy_lines OPTIONAL
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth_queries=>ty_results.
    METHODS node
      IMPORTING id            TYPE i
                parent        TYPE i
                iobjnm        TYPE rsiobjnm DEFAULT zzxxmla1_cl_bw_auth=>c_text_node
                name          TYPE csequence
                level         TYPE i
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_node.
    METHODS gp_line
      IMPORTING type          TYPE csequence
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_hierarchy_line.
    METHODS all_diagnoses
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_value_line.
    "! the answer of a query, asserted
    METHODS assert_answer
      IMPORTING results    TYPE zzxxmla1_cl_bw_auth_queries=>ty_results
                test       TYPE csequence
                hierarchy  TYPE csequence DEFAULT c_org
                node       TYPE csequence OPTIONAL
                !status    TYPE csequence
                members    TYPE string_table OPTIONAL.
ENDCLASS.


CLASS ltc_bw_auth_queries IMPLEMENTATION.

  METHOD node.
    result = VALUE #( nodeid = id parentid = parent iobjnm = iobjnm name = name level = level ).
  ENDMETHOD.

  METHOD gp_line.
    result = VALUE #( auth = 'ZA' iobjnm = c_doc hienm = 'ZCLDOC_ORG' version = '001'
                      node_iobjnm = zzxxmla1_cl_bw_auth=>c_text_node node = `GP` type = type ).
  ENDMETHOD.

  METHOD all_diagnoses.
    result = VALUE #( auth = 'ZA' iobjnm = c_diag sign = 'I' option = 'CP' low = `*` ).
  ENDMETHOD.

  METHOD run.
    " CLINIC > PRIMARY > GP > 001, 002; PRIMARY > PED > 006; DIAGNOSES > I10
    DATA(org) = VALUE zzxxmla1_cl_bw_auth=>ty_slice( iobjnm = c_doc hienm = 'ZCLDOC_ORG' version = '001'
                                                     nodes = VALUE #(
      ( node( id = 1 parent = 0 name = `CLINIC`  level = 1 ) )
      ( node( id = 2 parent = 1 name = `PRIMARY` level = 2 ) )
      ( node( id = 3 parent = 2 name = `GP`      level = 3 ) )
      ( node( id = 4 parent = 3 name = `001` iobjnm = c_doc level = 4 ) )
      ( node( id = 5 parent = 3 name = `002` iobjnm = c_doc level = 4 ) )
      ( node( id = 6 parent = 2 name = `PED`     level = 3 ) )
      ( node( id = 7 parent = 6 name = `006` iobjnm = c_doc level = 4 ) ) ) ).
    DATA(icd) = VALUE zzxxmla1_cl_bw_auth=>ty_slice( iobjnm = c_diag hienm = 'ZCLDIAG_ICD' nodes = VALUE #(
      ( node( id = 1 parent = 0 name = `DIAGNOSES` level = 1 ) )
      ( node( id = 2 parent = 1 name = `I10` iobjnm = c_diag level = 2 ) ) ) ).
    DATA(lines) = VALUE zzxxmla1_cl_bw_auth=>ty_lines(
      provider        = `ZCLVISITA`
      today           = '20261024'
      characteristics = VALUE #( ( c_diag ) ( c_doc ) )
      specials        = VALUE #( ( '0TCAIPROV' ) )
      auths           = VALUE #( ( 'ZA' ) )
      values          = VALUE #( BASE values ( auth = 'ZA' iobjnm = '0TCAIPROV' sign = 'I' option = 'CP' low = `*` ) )
      hierarchies     = hierarchies
      slices          = VALUE #( ( org ) ( icd ) ) ).
    DATA(queries) = zzxxmla1_cl_bw_auth_queries=>create(
      region          = zzxxmla1_cl_bw_auth=>create( lines )
      characteristics = VALUE #(
        ( iobjnm = c_doc values = VALUE #( ( `001` ) ( `002` ) ( `006` ) )
          hierarchies = VALUE #( ( hienm = 'ZCLDOC_ORG' version = '001' slice = org ) ) )
        ( iobjnm = c_diag values = VALUE #( ( `I10` ) )
          hierarchies = VALUE #( ( hienm = 'ZCLDIAG_ICD' slice = icd ) ) ) ) ).
    result = queries->run( VALUE #( ( first = `001` second = `I10` ) ( first = `006` second = `I10` ) ) ).
  ENDMETHOD.

  METHOD assert_answer.
    READ TABLE results INTO DATA(found) WITH KEY test = test hierarchy = hierarchy node = node.
    cl_abap_unit_assert=>assert_subrc( msg = |{ test } { hierarchy } { node } asked| ).
    cl_abap_unit_assert=>assert_equals( act = found-status exp = status
                                        msg = |{ test } { hierarchy } { node }: { found-message }| ).
    IF members IS SUPPLIED.
      cl_abap_unit_assert=>assert_equals( act = found-members exp = members msg = |{ test } { hierarchy } { node }| ).
    ENDIF.
  ENDMETHOD.

  METHOD subtree.
    DATA(results) = run( values = VALUE #( ( all_diagnoses( ) ) ) hierarchies = VALUE #( ( gp_line( '1' ) ) ) ).
    DATA(allowed) = zzxxmla1_cl_bw_auth=>c_status-allowed.
    DATA(no_auth) = zzxxmla1_cl_bw_auth=>c_status-no_auth.
    DATA(empty) = zzxxmla1_cl_bw_auth_queries=>c_empty.
    cl_abap_unit_assert=>assert_equals( act = results[ test = `HIERARCHIES` characteristic = c_doc ]-answer
                                        exp = c_org ).
    assert_answer( results = results test = `TOTAL` hierarchy = `` status = no_auth ).
    assert_answer( results = results test = `MEMBERS` status = allowed
                   members = VALUE #( ( `GP 0HIER_NODE` ) ( `001` ) ( `002` ) ) ).
    assert_answer( results = results test = `MEMBERS` hierarchy = `[ZCLDOC]` status = no_auth ).
    " re-rooted: GP on the first level
    assert_answer( results = results test = `LEVEL` node = `LEVEL00` status = allowed
                   members = VALUE #( ( `GP 0HIER_NODE` ) ) ).
    assert_answer( results = results test = `LEVEL` node = `LEVEL01` status = allowed
                   members = VALUE #( ( `001` ) ( `002` ) ) ).
    assert_answer( results = results test = `LEVEL` node = `LEVEL02` status = empty ).
    assert_answer( results = results test = `ROWS` node = `PRIMARY` status = no_auth ).
    assert_answer( results = results test = `CHILDREN` node = `GP` status = allowed
                   members = VALUE #( ( `001` ) ( `002` ) ) ).
    assert_answer( results = results test = `PARENT` node = `GP` status = empty ).
    assert_answer( results = results test = `PARENT` node = `001` status = allowed
                   members = VALUE #( ( `GP 0HIER_NODE` ) ) ).
    assert_answer( results = results test = `SLICER` hierarchy = `[ZCLDOC]` node = `001` status = allowed ).
    assert_answer( results = results test = `SLICER` hierarchy = `[ZCLDOC]` node = `006`
                   status = zzxxmla1_cl_bw_auth=>c_status-unknown ).
  ENDMETHOD.

  METHOD node_only.
    DATA(results) = run( values = VALUE #( ( all_diagnoses( ) ) ) hierarchies = VALUE #( ( gp_line( '0' ) ) ) ).
    " GP may not be expanded: .Members refused, its children empty, the level shows it
    assert_answer( results = results test = `MEMBERS` status = zzxxmla1_cl_bw_auth=>c_status-no_auth ).
    assert_answer( results = results test = `CHILDREN` node = `GP` status = zzxxmla1_cl_bw_auth_queries=>c_empty ).
    assert_answer( results = results test = `LEVEL` node = `LEVEL00` status = zzxxmla1_cl_bw_auth=>c_status-allowed
                   members = VALUE #( ( `GP 0HIER_NODE` ) ) ).
  ENDMETHOD.

  METHOD flat_values.
    DATA(results) = run( values = VALUE #( ( auth = 'ZA' iobjnm = c_doc sign = 'I' option = 'EQ' low = `001` )
                                           ( all_diagnoses( ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = results[ test = `HIERARCHIES` characteristic = c_doc ]-answer exp = `` ).
    cl_abap_unit_assert=>assert_equals( act = results[ test = `HIERARCHIES` characteristic = c_diag ]-answer
                                        exp = `ZCLDIAG_ICD` ).
    " a hierarchy without a line: refused, but its levels are empty
    assert_answer( results = results test = `MEMBERS` status = zzxxmla1_cl_bw_auth=>c_status-no_auth ).
    assert_answer( results = results test = `LEVEL` node = `LEVEL00` status = zzxxmla1_cl_bw_auth_queries=>c_empty ).
    assert_answer( results = results test = `SLICER` node = `GP` status = zzxxmla1_cl_bw_auth=>c_status-no_auth ).
    assert_answer( results = results test = `PAIR` hierarchy = `[ZCLDOC]` node = `001`
                   status = zzxxmla1_cl_bw_auth=>c_status-allowed ).
    assert_answer( results = results test = `PAIR` hierarchy = `[ZCLDOC]` node = `006`
                   status = zzxxmla1_cl_bw_auth=>c_status-unknown ).
    assert_answer( results = results test = `COMBINED` hierarchy = `[ZCLDIAG]`
                   status = zzxxmla1_cl_bw_auth=>c_status-allowed ).
  ENDMETHOD.

ENDCLASS.
