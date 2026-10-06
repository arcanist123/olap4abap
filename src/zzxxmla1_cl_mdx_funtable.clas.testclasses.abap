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
"! The table against what the reference server's BuiltinFunTable holds (scripts/funtable/DumpFunTable.java).
CLASS ltc_funtable DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    METHODS all_resolvers FOR TESTING.
    METHODS resolvers_by_name_and_syntax FOR TESTING.
    METHODS property_words FOR TESTING.
    METHODS reserved_words FOR TESTING.
ENDCLASS.

CLASS ltc_funtable IMPLEMENTATION.

  METHOD all_resolvers.
    cl_abap_unit_assert=>assert_equals( act = lines( zzxxmla1_cl_mdx_funtable=>instance( )->get_all( ) ) exp = 331 ).
  ENDMETHOD.

  METHOD resolvers_by_name_and_syntax.
    DATA(table) = zzxxmla1_cl_mdx_funtable=>instance( ).
    " <Hierarchy>.Members and <Level>.Members; Members(<String>) has function syntax
    DATA(members) = table->get_resolvers( name = `members` syntax = `Property` ).
    cl_abap_unit_assert=>assert_equals( act = lines( members ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = members[ 1 ]-signatures[ 1 ]-return_category exp = 8 ).
    cl_abap_unit_assert=>assert_equals( act = members[ 1 ]-signatures[ 1 ]-parameter_categories exp = VALUE zzxxmla1_cl_mdx_funtable=>ty_t_category( ( 3 ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( table->get_resolvers( name = `Members` syntax = `Function` ) ) exp = 1 ).
    " * is multiplication and the crossjoin of sets
    DATA(star) = table->get_resolvers( name = `*` syntax = `Infix` ).
    cl_abap_unit_assert=>assert_equals( act = lines( star ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = star[ 2 ]-kind exp = `CrossJoinFunDef$StarCrossJoinResolver` ).
    cl_abap_unit_assert=>assert_equals( act = lines( star[ 2 ]-signatures ) exp = 4 ).
    cl_abap_unit_assert=>assert_initial( table->get_resolvers( name = `Foo` syntax = `Function` ) ).
  ENDMETHOD.

  METHOD property_words.
    DATA(table) = zzxxmla1_cl_mdx_funtable=>instance( ).
    cl_abap_unit_assert=>assert_true( table->is_property( `children` ) ).
    cl_abap_unit_assert=>assert_true( table->is_property( `CurrentMember` ) ).
    cl_abap_unit_assert=>assert_false( table->is_property( `Item` ) ).
    cl_abap_unit_assert=>assert_false( table->is_property( `` ) ).
  ENDMETHOD.

  METHOD reserved_words.
    DATA(table) = zzxxmla1_cl_mdx_funtable=>instance( ).
    cl_abap_unit_assert=>assert_true( table->is_reserved( `basc` ) ).
    cl_abap_unit_assert=>assert_true( table->is_reserved( `SELF_AND_AFTER` ) ).
    cl_abap_unit_assert=>assert_false( table->is_reserved( `Store` ) ).
  ENDMETHOD.

ENDCLASS.