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
    "! a caption column: its value after the name, before the properties; without one the caption is the name
    METHODS caption_column FOR TESTING.
    "! the empty member (blank keys) is a member like any other, also on the first row
    METHODS empty_member FOR TESTING.
    "! the values of a level's properties follow its key and name; a member takes the ones of its first row
    METHODS properties FOR TESTING.
    "! order keys compare as the database orders the keys: numbers by value, the empty key first
    METHODS order_key FOR TESTING.
    "! a level with an ordinal column (a room by its compound key, keyed by the SID): its order key has the
    "! ordinal's, then the key's; the conditions of Lag/Lead and ranges compare the ordinal first
    METHODS ordinal_column FOR TESTING.
    "! a dimension that shows only its members with facts is read from the rows whose key is in the fact table
    METHODS member_table FOR TESTING.
    "! a measure of an aggregator other than sum and count is refused: its value would be a sum
    METHODS check_aggregator FOR TESTING RAISING cx_static_check.
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
    DATA(canada) = |{ tab }0Canada|.
    DATA(vancouver) = |{ canada }{ tab }0Vancouver|.
    DATA(usa) = |{ tab }0USA|.
    DATA(portland) = |{ usa }{ tab }0Portland|.
    DATA(seattle) = |{ usa }{ tab }0Seattle|.
    cl_abap_unit_assert=>assert_equals( act = members exp = VALUE zzxxmla1_cl_model=>ty_t_member(
      ( level_no = 1 key = `Canada` name = `Canada` caption = `Canada` path = `Canada` unique_name = `[Store].[Canada]`
        children = 1 order_key = canada )
      ( level_no = 2 key = `Vancouver` name = `Vancouver` caption = `Vancouver` path = |Canada{ tab }Vancouver|
        unique_name = `[Store].[Canada].[Vancouver]` parent = `[Store].[Canada]` children = 1 order_key = vancouver )
      ( level_no = 3 key = `19` name = `19` caption = `19` path = |Canada{ tab }Vancouver{ tab }19|
        unique_name = `[Store].[Canada].[Vancouver].[19]` parent = `[Store].[Canada].[Vancouver]`
        order_key = |{ vancouver }{ tab }0P0219| )
      ( level_no = 1 key = `USA` name = `USA` caption = `USA` path = `USA` unique_name = `[Store].[USA]` children = 2
        order_key = usa )
      ( level_no = 2 key = `Portland` name = `Portland` caption = `Portland` path = |USA{ tab }Portland|
        unique_name = `[Store].[USA].[Portland]` parent = `[Store].[USA]` children = 1 order_key = portland )
      ( level_no = 3 key = `11` name = `11` caption = `11` path = |USA{ tab }Portland{ tab }11|
        unique_name = `[Store].[USA].[Portland].[11]` parent = `[Store].[USA].[Portland]`
        order_key = |{ portland }{ tab }0P0211| )
      ( level_no = 2 key = `Seattle` name = `Seattle` caption = `Seattle` path = |USA{ tab }Seattle|
        unique_name = `[Store].[USA].[Seattle]` parent = `[Store].[USA]` children = 2 order_key = seattle )
      ( level_no = 3 key = `15` name = `15` caption = `15` path = |USA{ tab }Seattle{ tab }15|
        unique_name = `[Store].[USA].[Seattle].[15]` parent = `[Store].[USA].[Seattle]`
        order_key = |{ seattle }{ tab }0P0215| )
      ( level_no = 3 key = `16` name = `16` caption = `16` path = |USA{ tab }Seattle{ tab }16|
        unique_name = `[Store].[USA].[Seattle].[16]` parent = `[Store].[USA].[Seattle]`
        order_key = |{ seattle }{ tab }0P0216| ) ) ).
  ENDMETHOD.

  METHOD ordinal_column.
    DATA(rooms) = VALUE zzxxmla1_cl_model=>ty_hierarchy(
      dim_name = `Room` hier_name = `Room` unique_name = `[Room]` has_all = abap_true dim_table = `V_ROOM`
      levels   = VALUE #( ( level_no = 1 level_name = `Room` key_column = `SID` name_column = `COMPOUND_KEY`
                            ordinal_column = `COMPOUND_KEY` data_type = `Numeric` unique_members = abap_true ) ) ).
    " the key and the name, which is the ordinal too (read once): SID 7 is NORTH/R05, loaded after SOUTH/R01 (SID 3)
    DATA(members) = zzxxmla1_cl_model=>members_of_rows(
      hierarchy = rooms
      rows      = VALUE #( ( VALUE #( ( `7` ) ( `NORTH/R05` ) ) )
                           ( VALUE #( ( `3` ) ( `SOUTH/R01` ) ) ) ) ).
    DATA(tab) = zzxxmla1_cl_model=>c_separator.
    cl_abap_unit_assert=>assert_equals(
      act = VALUE string_table( FOR m IN members ( |{ m-key } { m-name } { m-order_key }| ) )
      exp = VALUE string_table( ( |7 NORTH/R05 { tab }0NORTH/R05{ tab }0P017| )
                                ( |3 SOUTH/R01 { tab }0SOUTH/R01{ tab }0P013| ) ) ).
    " an ordinal column of its own: read after the key, before the name
    rooms-levels[ 1 ]-name_column = `ZCLROOM`.
    members = zzxxmla1_cl_model=>members_of_rows( hierarchy = rooms
                                                  rows      = VALUE #( ( VALUE #( ( `7` ) ( `NORTH/R05` ) ( `R05` ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = |{ members[ 1 ]-name } { members[ 1 ]-order_key }|
                                        exp = |R05 { tab }0NORTH/R05{ tab }0P017| ).
    rooms-levels[ 1 ]-name_column = `COMPOUND_KEY`.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_model=>order_condition( hierarchy = rooms level_no = 1 path = `7` operator = `>` )
      exp = `( ( ( "COMPOUND_KEY" > ( SELECT MAX( "COMPOUND_KEY" ) FROM "V_ROOM" WHERE "SID" = '7' ) OR ` &&
            `( "COMPOUND_KEY" = ( SELECT MAX( "COMPOUND_KEY" ) FROM "V_ROOM" WHERE "SID" = '7' ) AND "SID" > '7' ) ) ) )` ).
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

  METHOD caption_column.
    DATA(store) = hierarchy( `NAME` ).
    store-levels[ 3 ]-caption_column = `TXT`.
    store-levels[ 3 ]-properties = VALUE #( ( name = `Store Type` column = `TYPE` data_type = `String` ) ).
    DATA(members) = zzxxmla1_cl_model=>members_of_rows(
      hierarchy = store
      rows      = VALUE #( ( VALUE #( ( `USA` ) ( `Seattle` ) ( `15` ) ( `0015` ) ( `Store 15` ) ( `Supermarket` ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( members ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = members[ 3 ]-name exp = `0015` ).
    cl_abap_unit_assert=>assert_equals( act = members[ 3 ]-caption exp = `Store 15` ).
    cl_abap_unit_assert=>assert_equals( act = members[ 3 ]-unique_name exp = `[Store].[USA].[Seattle].[0015]` ).
    cl_abap_unit_assert=>assert_equals( act = members[ 3 ]-properties exp = VALUE string_table( ( `Supermarket` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = members[ 2 ]-caption exp = `Seattle` ).
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

  METHOD order_key.
    DATA(keys) = VALUE string_table( ( `` ) ( `-10` ) ( `-9.5` ) ( `-9` ) ( `-0.5` ) ( `0` ) ( `0.25` ) ( `1` ) ( `1.5` )
                                     ( `9` ) ( `10` ) ( `010.50` ) ( `100` ) ).
    LOOP AT keys INTO DATA(key) FROM 2.
      DATA(lower) = keys[ sy-tabix - 1 ].
      DATA(before) = zzxxmla1_cl_model=>order_key( key = lower numeric = abap_true ).
      DATA(after) = zzxxmla1_cl_model=>order_key( key = key numeric = abap_true ).
      cl_abap_unit_assert=>assert_true( act = xsdbool( before < after ) msg = |{ lower } < { key }| ).
    ENDLOOP.
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_model=>order_key( key = `-0` numeric = abap_true )
                                        exp = zzxxmla1_cl_model=>order_key( key = `0.00` numeric = abap_true ) ).
    " texts as they are, also texts of digits
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_model=>order_key( key = `10` numeric = abap_false ) exp = `10` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_model=>order_key( key = `1E3` numeric = abap_true ) exp = `1E3` ).
  ENDMETHOD.

  METHOD member_table.
    DATA(rooms) = VALUE zzxxmla1_cl_model=>ty_hierarchy( dim_table = `V_ROOM` key_column = `SID` fk_column = `SID_ROOM`
                                                        fact_table = `/BIC/FCLINIC` ).
    cl_abap_unit_assert=>assert_equals( act = zzxxmla1_cl_model=>member_table( rooms ) exp = `"V_ROOM"` ).
    rooms-members_with_facts = abap_true.
    cl_abap_unit_assert=>assert_equals(
      act = zzxxmla1_cl_model=>member_table( rooms )
      exp = `( SELECT * FROM "V_ROOM" WHERE "SID" IN ( SELECT "SID_ROOM" FROM "/BIC/FCLINIC" ) ) AS mf` ).
  ENDMETHOD.

  METHOD check_aggregator.
    zzxxmla1_cl_model=>check_aggregator( VALUE #( name = `Units` aggregator = `sum` ) ).
    zzxxmla1_cl_model=>check_aggregator( VALUE #( name = `Fact Count` aggregator = `count` ) ).
    LOOP AT VALUE string_table( ( `min` ) ( `max` ) ( `avg` ) ( `distinct-count` ) ) INTO DATA(aggregator).
      TRY.
          zzxxmla1_cl_model=>check_aggregator( VALUE #( name = `Units` aggregator = aggregator ) ).
          cl_abap_unit_assert=>fail( |no fault for { aggregator }| ).
        CATCH zzxxmla1_cx_xmla INTO DATA(fault).
          cl_abap_unit_assert=>assert_equals(
            act = fault->description
            exp = |olap4abap Error:Measure 'Units': the aggregator { aggregator } is not implemented yet| ).
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
