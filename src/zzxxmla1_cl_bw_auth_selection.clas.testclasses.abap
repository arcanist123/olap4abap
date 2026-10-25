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
"! The selection of statements in BW's names on $ZCLVISITA (the clinic demo's aDSO), through the engine's members.
CLASS ltc_selection DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    CONSTANTS c_org TYPE string VALUE `[ZCLDOC                        ZCLDOC_ORG                    001]`.
    CONSTANTS c_icd TYPE string VALUE `[ZCLDIAG                       ZCLDIAG_ICD]`.
    CONSTANTS c_card TYPE string VALUE `[CARD                            0HIER_NODE                    ]`.
    CLASS-METHODS selection
      IMPORTING statement     TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth_selection=>ty_selection.
    METHODS children_with_slicer FOR TESTING.
    METHODS bw_hierarchy_without_all FOR TESTING.
    METHODS flat_members FOR TESTING.
    METHODS member_texts FOR TESTING.
ENDCLASS.

CLASS ltc_selection IMPLEMENTATION.

  METHOD selection.
    TRY.
        DATA(parsed) = zzxxmla1_cl_mdx_parser=>parse( statement ).
        DATA(members) = NEW zzxxmla1_cl_mdx_engine( catalog = `` bw_names = abap_true )->members( parsed-query ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>fail( error->description ).
    ENDTRY.
    result = zzxxmla1_cl_bw_auth_selection=>of_members( members ).
  ENDMETHOD.

  METHOD children_with_slicer.
    DATA(selection) = selection( |SELECT \{[Measures].[ZCLVISNO]\} ON 0, \{{ c_org }.{ c_card }.Children\} ON 1 | &&
                                 |FROM [$ZCLVISITA] WHERE ([ZCLDIAG].[A09])| ).
    cl_abap_unit_assert=>assert_equals( act = selection-names exp = VALUE string_table( ( `Slicer` ) ( `Axis0` )
                                                                                        ( `Axis1` ) ) ).
    DATA(a09) = VALUE zzxxmla1_cl_bw_auth=>ty_member( iobjnm = 'ZCLDIAG' kind = zzxxmla1_cl_bw_auth=>c_kind-value
                                                      value = `A09` named = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = selection-factors[ 1 ] exp = VALUE zzxxmla1_cl_bw_auth=>ty_selection(
                                                                                ( VALUE #( ( a09 ) ) ) ) ).
    " the measure is no characteristic: one tuple without members
    cl_abap_unit_assert=>assert_equals( act = selection-factors[ 2 ] exp = VALUE zzxxmla1_cl_bw_auth=>ty_selection(
                                                                                ( VALUE #( ) ) ) ).
    " CARD's children are leaves of ZCLDOC, not named
    cl_abap_unit_assert=>assert_not_initial( selection-factors[ 3 ] ).
    LOOP AT selection-factors[ 3 ] INTO DATA(tuple).
      cl_abap_unit_assert=>assert_equals( act = lines( tuple ) exp = 1 ).
      cl_abap_unit_assert=>assert_equals( act = tuple[ 1 ]-node_iobjnm exp = 'ZCLDOC' ).
      cl_abap_unit_assert=>assert_false( tuple[ 1 ]-named ).
    ENDLOOP.
    " named: the node Children starts from and the slicer's value
    DATA(card) = VALUE zzxxmla1_cl_bw_auth=>ty_member( iobjnm = 'ZCLDOC' kind = zzxxmla1_cl_bw_auth=>c_kind-node
                                                       value = `CARD` hienm = 'ZCLDOC_ORG' version = '001'
                                                       node_iobjnm = '0HIER_NODE' named = abap_true ).
    cl_abap_unit_assert=>assert_equals( act = selection-named exp = VALUE zzxxmla1_cl_bw_auth=>ty_tuple( ( card )
                                                                                                    ( a09 ) ) ).
    cl_abap_unit_assert=>assert_false( selection-empty ).
  ENDMETHOD.

  METHOD bw_hierarchy_without_all.
    DATA(selection) = selection( |SELECT \{[Measures].[ZCLVISNO]\} ON 0, \{{ c_icd }.Members\} ON 1 | &&
                                 |FROM [$ZCLVISITA]| ).
    DATA(rows) = selection-factors[ 2 ].
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ][ 1 ]-value exp = `DIAGNOSES` ).
    LOOP AT rows INTO DATA(tuple).
      cl_abap_unit_assert=>assert_equals( act = tuple[ 1 ]-kind exp = zzxxmla1_cl_bw_auth=>c_kind-node ).
    ENDLOOP.
    " LEVEL00 of a BW hierarchy is its roots
    selection = selection( |SELECT \{[Measures].[ZCLVISNO]\} ON 0, \{{ c_icd }.[LEVEL00].Members\} ON 1 | &&
                           |FROM [$ZCLVISITA]| ).
    cl_abap_unit_assert=>assert_equals( act = lines( selection-factors[ 2 ] ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = selection-factors[ 2 ][ 1 ][ 1 ]-value exp = `DIAGNOSES` ).
  ENDMETHOD.

  METHOD flat_members.
    DATA(selection) = selection( `SELECT {[Measures].[ZCLVISNO]} ON 0, {[ZCLDIAG].Members} ON 1 FROM [$ZCLVISITA]` ).
    DATA(rows) = selection-factors[ 2 ].
    cl_abap_unit_assert=>assert_equals( act = rows[ 1 ][ 1 ]-kind exp = zzxxmla1_cl_bw_auth=>c_kind-aggregate ).
    cl_abap_unit_assert=>assert_equals( act = rows[ 2 ][ 1 ]-kind exp = zzxxmla1_cl_bw_auth=>c_kind-value ).
    " the not-assigned value is the key ''
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( rows[ table_line = VALUE zzxxmla1_cl_bw_auth=>ty_tuple(
      ( iobjnm = 'ZCLDIAG' kind = zzxxmla1_cl_bw_auth=>c_kind-value ) ) ] ) ) ).
    cl_abap_unit_assert=>assert_initial( selection-named ).
  ENDMETHOD.

  METHOD member_texts.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_auth_selection=>member_text( VALUE #( iobjnm = 'ZCLDOC' kind = zzxxmla1_cl_bw_auth=>c_kind-value
                                                                  value = `001` ) )
      exp = `ZCLDOC '001'` ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_auth_selection=>member_text( VALUE #( iobjnm = 'ZCLDOC'
                                                                  kind = zzxxmla1_cl_bw_auth=>c_kind-aggregate ) )
      exp = `ZCLDOC :` ).
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_bw_auth_selection=>member_text( VALUE #( iobjnm = 'ZCLDOC' kind = zzxxmla1_cl_bw_auth=>c_kind-node
                                                                  value = `CARD` hienm = 'ZCLDOC_ORG' version = '001'
                                                                  node_iobjnm = '0HIER_NODE' ) )
      exp = `ZCLDOC ZCLDOC_ORG 001 CARD (0HIER_NODE)` ).
  ENDMETHOD.

ENDCLASS.
