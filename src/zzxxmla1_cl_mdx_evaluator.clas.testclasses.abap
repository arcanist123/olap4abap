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
*"* use this source file for your ABAP unit test classes
CLASS ltc_evaluator DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    CLASS-DATA reader TYPE REF TO zzxxmla1_cl_mdx_schema_reader.
    CLASS-DATA facts TYPE REF TO zzxxmla1_cl_mdx_facts.
    DATA evaluator TYPE REF TO zzxxmla1_cl_mdx_evaluator.
    CLASS-METHODS class_setup RAISING zzxxmla1_cx_xmla.
    METHODS setup.
    "! The member of the unique name, e.g. [Store].[USA].[WA].
    METHODS member
      IMPORTING unique_name   TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_member.
    METHODS hierarchy
      IMPORTING unique_name   TYPE string
      RETURNING VALUE(result) TYPE i.
    METHODS default_context FOR TESTING.
    METHODS cell_of_context FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS restore_to_savepoint FOR TESTING.
    METHODS nested_savepoints FOR TESTING.
    METHODS savepoint_twice FOR TESTING.
    METHODS flags_restored FOR TESTING.
    METHODS push_copies_context FOR TESTING.
    METHODS slicer_context FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS current_is_empty FOR TESTING RAISING zzxxmla1_cx_xmla.
ENDCLASS.

CLASS ltc_evaluator IMPLEMENTATION.

  METHOD class_setup.
    reader = zzxxmla1_cl_mdx_schema_reader=>for_cube( catalog = `` name = `ZFMSALES` ).
    facts = NEW #( cube = reader->cube hierarchies = reader->get_model_hierarchies( ) measures = reader->measures ).
  ENDMETHOD.

  METHOD setup.
    evaluator = zzxxmla1_cl_mdx_evaluator=>create( schema_reader = reader facts = facts ).
  ENDMETHOD.

  METHOD hierarchy.
    DATA(hierarchies) = reader->get_hierarchies( ).
    result = hierarchies[ unique_name = unique_name ]-id.
  ENDMETHOD.

  METHOD member.
    DATA members TYPE zzxxmla1_cl_mdx_evaluator=>ty_t_member.
    SPLIT unique_name AT `].` INTO DATA(hierarchy_name) DATA(rest) ##NEEDED.
    IF hierarchy_name = `[Measures`.
      members = VALUE #( FOR i = 1 UNTIL i > lines( reader->measures ) ( reader->measure_member( i ) ) ).
    ELSE.
      members = reader->get_hierarchy_members( hierarchy( hierarchy_name && `]` ) ).
    ENDIF.
    result = members[ unique_name = unique_name ].
  ENDMETHOD.

  METHOD default_context.
    DATA(members) = evaluator->get_members( ).
    cl_abap_unit_assert=>assert_equals( act = lines( members ) exp = lines( reader->get_hierarchies( ) ) ).
    cl_abap_unit_assert=>assert_equals( act = members[ 1 ]-unique_name exp = `[Measures].[Unit Sales]` ).
    cl_abap_unit_assert=>assert_equals( act = evaluator->get_context( hierarchy( `[Store]` ) )-unique_name
                                        exp = `[Store].[All Stores]` ).
  ENDMETHOD.

  METHOD cell_of_context.
    cl_abap_unit_assert=>assert_equals( act = evaluator->evaluate_current( )-number exp = CONV f( 266773 ) ).
    evaluator->set_context( member( `[Store].[USA].[WA].[Bremerton].[Store 3]` ) ).
    cl_abap_unit_assert=>assert_equals( act = evaluator->evaluate_current( )-number exp = CONV f( 24576 ) ).
    " a member above the bottom level: the facts of its descendants
    evaluator->set_context( member( `[Store].[USA].[WA]` ) ).
    cl_abap_unit_assert=>assert_equals( act = evaluator->evaluate_current( )-number exp = CONV f( 124366 ) ).
    evaluator->set_context( member( `[Store].[All Stores]` ) ).
    evaluator->set_context( member( `[Measures].[Store Cost]` ) ).
    cl_abap_unit_assert=>assert_equals( act = evaluator->evaluate_current( )-number exp = CONV f( '225627.2336' ) ).
  ENDMETHOD.

  METHOD restore_to_savepoint.
    DATA(store) = hierarchy( `[Store]` ).
    DATA(savepoint) = evaluator->savepoint( ).
    DATA(previous) = evaluator->set_context( member( `[Store].[Mexico].[Guerrero].[Acapulco].[Store 1]` ) ).
    cl_abap_unit_assert=>assert_equals( act = previous-unique_name exp = `[Store].[All Stores]` ).
    evaluator->set_context( member( `[Store].[USA].[WA].[Bellingham].[Store 2]` ) ).
    evaluator->set_context( member( `[Measures].[Store Cost]` ) ).
    cl_abap_unit_assert=>assert_equals( act = evaluator->get_context( store )-unique_name
                                        exp = `[Store].[USA].[WA].[Bellingham].[Store 2]` ).
    evaluator->restore( savepoint ).
    cl_abap_unit_assert=>assert_equals( act = evaluator->get_context( store )-unique_name exp = `[Store].[All Stores]` ).
    cl_abap_unit_assert=>assert_equals( act = evaluator->get_context( 0 )-unique_name exp = `[Measures].[Unit Sales]` ).
  ENDMETHOD.

  METHOD nested_savepoints.
    DATA(store) = hierarchy( `[Store]` ).
    DATA(outer) = evaluator->savepoint( ).
    evaluator->set_context( member( `[Store].[Mexico].[Guerrero].[Acapulco].[Store 1]` ) ).
    DATA(inner) = evaluator->savepoint( ).
    evaluator->set_context( member( `[Store].[USA].[WA].[Bellingham].[Store 2]` ) ).
    evaluator->restore( inner ).
    cl_abap_unit_assert=>assert_equals( act = evaluator->get_context( store )-unique_name
                                        exp = `[Store].[Mexico].[Guerrero].[Acapulco].[Store 1]` ).
    evaluator->restore( outer ).
    cl_abap_unit_assert=>assert_equals( act = evaluator->get_context( store )-unique_name exp = `[Store].[All Stores]` ).
  ENDMETHOD.

  METHOD savepoint_twice.
    " a savepoint right after a savepoint is the same one
    DATA(store) = hierarchy( `[Store]` ).
    DATA(first) = evaluator->savepoint( ).
    DATA(second) = evaluator->savepoint( ).
    cl_abap_unit_assert=>assert_equals( act = second exp = first ).
    evaluator->set_context( member( `[Store].[Mexico].[Guerrero].[Acapulco].[Store 1]` ) ).
    evaluator->restore( second ).
    cl_abap_unit_assert=>assert_equals( act = evaluator->get_context( store )-unique_name exp = `[Store].[All Stores]` ).
  ENDMETHOD.

  METHOD flags_restored.
    DATA(savepoint) = evaluator->savepoint( ).
    evaluator->set_non_empty( abap_true ).
    evaluator->set_eval_axes( abap_true ).
    cl_abap_unit_assert=>assert_true( evaluator->is_non_empty( ) ).
    cl_abap_unit_assert=>assert_true( evaluator->is_eval_axes( ) ).
    evaluator->restore( savepoint ).
    cl_abap_unit_assert=>assert_false( evaluator->is_non_empty( ) ).
    cl_abap_unit_assert=>assert_false( evaluator->is_eval_axes( ) ).
  ENDMETHOD.

  METHOD push_copies_context.
    DATA(store) = hierarchy( `[Store]` ).
    evaluator->set_context( member( `[Store].[Mexico].[Guerrero].[Acapulco].[Store 1]` ) ).
    DATA(child) = evaluator->push( ).
    cl_abap_unit_assert=>assert_equals( act = child->get_context( store )-unique_name
                                        exp = `[Store].[Mexico].[Guerrero].[Acapulco].[Store 1]` ).
    child->set_context( member( `[Store].[USA].[WA].[Bellingham].[Store 2]` ) ).
    cl_abap_unit_assert=>assert_equals( act = evaluator->get_context( store )-unique_name
                                        exp = `[Store].[Mexico].[Guerrero].[Acapulco].[Store 1]` ).
    cl_abap_unit_assert=>assert_bound( child->get_parent( ) ).
  ENDMETHOD.

  METHOD slicer_context.
    evaluator->set_slicer_context( VALUE #( ( member( `[Store].[USA].[WA].[Bremerton].[Store 3]` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( evaluator->get_slicer_members( ) ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = evaluator->evaluate_current( )-number exp = CONV f( 24576 ) ).
  ENDMETHOD.

  METHOD current_is_empty.
    cl_abap_unit_assert=>assert_false( evaluator->current_is_empty( ) ).
    " store 1 has no sales
    evaluator->set_context( member( `[Store].[Mexico].[Guerrero].[Acapulco].[Store 1]` ) ).
    cl_abap_unit_assert=>assert_true( evaluator->evaluate_current( )-empty ).
    cl_abap_unit_assert=>assert_true( evaluator->current_is_empty( ) ).
  ENDMETHOD.

ENDCLASS.
