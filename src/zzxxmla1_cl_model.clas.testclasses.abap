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
CLASS ltc_model DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    "! the rows of the level columns become a tree in hierarchy order, with the children counted
    METHODS members_of_rows FOR TESTING.
    "! a level with a name column of its own: keyed by one column, named by the other
    METHODS name_column FOR TESTING.
    "! the empty member (blank keys) is a member like any other, also on the first row
    METHODS empty_member FOR TESTING.
    "! the values of a level's properties follow its key and name; a member takes the ones of its first row
    METHODS properties FOR TESTING.
    METHODS hierarchy
      IMPORTING name_column   TYPE string OPTIONAL
      RETURNING VALUE(result) TYPE zzxxmla1_cl_model=>ty_hierarchy.
ENDCLASS.

CLASS ltc_model IMPLEMENTATION.

  METHOD hierarchy.
    result = VALUE #( dim_name = `Store` hier_name = `Store` unique_name = `[Store]` has_all = abap_true
                      levels = VALUE #( ( level_no = 1 level_name = `Country` key_column = `C` name_column = `C`
                                          data_type = `String` unique_members = abap_true )
                                        ( level_no = 2 level_name = `City` key_column = `T` name_column = `T`
                                          data_type = `String` )
                                        ( level_no = 3 level_name = `Store` key_column = `S`
                                          name_column = COND #( WHEN name_column IS INITIAL THEN `S`
                                                                ELSE name_column )
                                          data_type = `Numeric` unique_members = abap_true ) ) ).
  ENDMETHOD.

  METHOD members_of_rows.
    DATA(members) = zzxxmla1_cl_model=>members_of_rows(
      hierarchy = hierarchy( )
      rows      = VALUE #( ( VALUE #( ( `Canada` ) ( `Vancouver` ) ( `19` ) ) )
                           ( VALUE #( ( `USA` ) ( `Portland` ) ( `11` ) ) )
                           ( VALUE #( ( `USA` ) ( `Seattle` ) ( `15` ) ) )
                           ( VALUE #( ( `USA` ) ( `Seattle` ) ( `16` ) ) ) ) ).
    DATA(tab) = zzxxmla1_cl_model=>c_separator.
    cl_abap_unit_assert=>assert_equals( act = members exp = VALUE zzxxmla1_cl_model=>ty_t_member(
      ( level_no = 1 key = `Canada` name = `Canada` path = `Canada` unique_name = `[Store].[Canada]` children = 1 )
      ( level_no = 2 key = `Vancouver` name = `Vancouver` path = |Canada{ tab }Vancouver|
        unique_name = `[Store].[Canada].[Vancouver]` parent = `[Store].[Canada]` children = 1 )
      ( level_no = 3 key = `19` name = `19` path = |Canada{ tab }Vancouver{ tab }19|
        unique_name = `[Store].[Canada].[Vancouver].[19]` parent = `[Store].[Canada].[Vancouver]` )
      ( level_no = 1 key = `USA` name = `USA` path = `USA` unique_name = `[Store].[USA]` children = 2 )
      ( level_no = 2 key = `Portland` name = `Portland` path = |USA{ tab }Portland|
        unique_name = `[Store].[USA].[Portland]` parent = `[Store].[USA]` children = 1 )
      ( level_no = 3 key = `11` name = `11` path = |USA{ tab }Portland{ tab }11|
        unique_name = `[Store].[USA].[Portland].[11]` parent = `[Store].[USA].[Portland]` )
      ( level_no = 2 key = `Seattle` name = `Seattle` path = |USA{ tab }Seattle|
        unique_name = `[Store].[USA].[Seattle]` parent = `[Store].[USA]` children = 2 )
      ( level_no = 3 key = `15` name = `15` path = |USA{ tab }Seattle{ tab }15|
        unique_name = `[Store].[USA].[Seattle].[15]` parent = `[Store].[USA].[Seattle]` )
      ( level_no = 3 key = `16` name = `16` path = |USA{ tab }Seattle{ tab }16|
        unique_name = `[Store].[USA].[Seattle].[16]` parent = `[Store].[USA].[Seattle]` ) ) ).
  ENDMETHOD.

  METHOD name_column.
    DATA(members) = zzxxmla1_cl_model=>members_of_rows(
      hierarchy = hierarchy( `NAME` )
      rows      = VALUE #( ( VALUE #( ( `USA` ) ( `Seattle` ) ( `15` ) ( `Store [15]` ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( members ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = members[ 3 ]-key exp = `15` ).
    cl_abap_unit_assert=>assert_equals( act = members[ 3 ]-name exp = `Store [15]` ).
    cl_abap_unit_assert=>assert_equals( act = members[ 3 ]-unique_name exp = `[Store].[USA].[Seattle].[Store [15]]]` ).
  ENDMETHOD.

  METHOD empty_member.
    DATA(members) = zzxxmla1_cl_model=>members_of_rows(
      hierarchy = hierarchy( )
      rows      = VALUE #( ( VALUE #( ( `` ) ( `` ) ( `0` ) ) )
                           ( VALUE #( ( `USA` ) ( `` ) ( `1` ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( members ) exp = 6 ).
    cl_abap_unit_assert=>assert_equals( act = members[ 1 ]-unique_name exp = `[Store].[]` ).
    cl_abap_unit_assert=>assert_equals( act = members[ 2 ]-unique_name exp = `[Store].[].[]` ).
    cl_abap_unit_assert=>assert_equals( act = members[ 5 ]-unique_name exp = `[Store].[USA].[]` ).
  ENDMETHOD.

  METHOD properties.
    DATA(store) = hierarchy( `NAME` ).
    store-levels[ 3 ]-properties = VALUE #( ( name = `Store Type` column = `TYPE` data_type = `String` )
                                            ( name = `Store Sqft` column = `SQFT` data_type = `Numeric` ) ).
    DATA(members) = zzxxmla1_cl_model=>members_of_rows(
      hierarchy = store
      rows      = VALUE #( ( VALUE #( ( `USA` ) ( `Seattle` ) ( `15` ) ( `Store 15` ) ( `Supermarket` ) ( `21215` ) ) )
                           ( VALUE #( ( `USA` ) ( `Seattle` ) ( `15` ) ( `Store 15` ) ( `Other` ) ( `1` ) ) )
                           ( VALUE #( ( `USA` ) ( `Seattle` ) ( `16` ) ( `Store 16` ) ( `` ) ( `0` ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( members ) exp = 4 ).
    cl_abap_unit_assert=>assert_initial( members[ 2 ]-properties ).
    cl_abap_unit_assert=>assert_equals( act = members[ 3 ]-properties exp = VALUE string_table( ( `Supermarket` )
                                                                                                 ( `21215` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = members[ 4 ]-name exp = `Store 16` ).
    cl_abap_unit_assert=>assert_equals( act = members[ 4 ]-properties exp = VALUE string_table( ( `` ) ( `0` ) ) ).
  ENDMETHOD.

ENDCLASS.
