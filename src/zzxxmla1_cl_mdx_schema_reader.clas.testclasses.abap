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
"! Identifiers of the cube ZFMSALES looked up as the reference server looks them up (captured from the container with
"! SELECT id ON 0 FROM [ZFMSALES]: a dimension, hierarchy or member became the default member or the member, a level
"! gave "expression is not a set", a missing object "MDX object ... not found").
CLASS ltc_lookup DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    CLASS-DATA reader TYPE REF TO zzxxmla1_cl_mdx_schema_reader.
    CLASS-METHODS class_setup RAISING zzxxmla1_cx_xmla.
    "! The kind of the element and, for a member, its unique name; for a hierarchy, dimension or level its name.
    METHODS assert_lookup
      IMPORTING mdx      TYPE string
                kind     TYPE string
                name     TYPE string OPTIONAL.
    METHODS dimensions_and_hierarchies FOR TESTING.
    METHODS levels FOR TESTING.
    METHODS members FOR TESTING.
    METHODS not_found FOR TESTING.
    METHODS case_insensitive FOR TESTING.
    METHODS unknown_cube FOR TESTING.
ENDCLASS.

CLASS ltc_lookup IMPLEMENTATION.

  METHOD class_setup.
    reader = zzxxmla1_cl_mdx_schema_reader=>for_cube( catalog = `` name = `ZFMSALES` ).
  ENDMETHOD.

  METHOD assert_lookup.
    TRY.
        DATA(id) = zzxxmla1_cl_mdx_parser=>parse_expression( mdx ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>fail( error->description ).
    ENDTRY.
    DATA(element) = reader->lookup_compound( id->segments ).
    cl_abap_unit_assert=>assert_equals( act = element-kind exp = kind msg = mdx ).
    CASE kind.
      WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-member.
        cl_abap_unit_assert=>assert_equals( act = element-member-unique_name exp = name msg = mdx ).
      WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-dimension.
        cl_abap_unit_assert=>assert_equals( act = reader->get_dimension( element-id )-unique_name exp = name msg = mdx ).
      WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-hierarchy.
        cl_abap_unit_assert=>assert_equals( act = reader->get_hierarchy( element-id )-unique_name exp = name msg = mdx ).
      WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-level.
        cl_abap_unit_assert=>assert_equals( act = reader->get_level( element-id )-unique_name exp = name msg = mdx ).
    ENDCASE.
  ENDMETHOD.

  METHOD dimensions_and_hierarchies.
    assert_lookup( mdx = `[Customers]` kind = `DIMENSION` name = `[Customers]` ).
    assert_lookup( mdx = `[Store]` kind = `DIMENSION` name = `[Store]` ).
    assert_lookup( mdx = `[Measures]` kind = `DIMENSION` name = `[Measures]` ).
    " a hierarchy named [dimension.hierarchy] at cube level, the version 3 style
    assert_lookup( mdx = `[Customers.City]` kind = `HIERARCHY` name = `[Customers.City]` ).
    assert_lookup( mdx = `[Customers.Customer Id]` kind = `HIERARCHY` name = `[Customers.Customer Id]` ).
    assert_lookup( mdx = `[Measures].[Measures]` kind = `HIERARCHY` name = `[Measures]` ).
    " the dimension's unnamed hierarchy has the dimension's name
    assert_lookup( mdx = `[Store].[Store]` kind = `HIERARCHY` name = `[Store]` ).
  ENDMETHOD.

  METHOD levels.
    assert_lookup( mdx = `[Store].[Store Country]` kind = `LEVEL` name = `[Store].[Store Country]` ).
    assert_lookup( mdx = `[Customers].[City]` kind = `LEVEL` name = `[Customers].[City]` ).
    assert_lookup( mdx = `[Customers.City].[City]` kind = `LEVEL` name = `[Customers.City].[City]` ).
    assert_lookup( mdx = `[Store].[(All)]` kind = `LEVEL` name = `[Store].[(All)]` ).
    assert_lookup( mdx = `[Time].[Year]` kind = `LEVEL` name = `[Time].[Year]` ).
    assert_lookup( mdx = `[Measures].[MeasuresLevel]` kind = `LEVEL` name = `[Measures].[MeasuresLevel]` ).
  ENDMETHOD.

  METHOD members.
    assert_lookup( mdx = `[Store].[All Stores]` kind = `MEMBER` name = `[Store].[All Stores]` ).
    " below the All member: [Store].[USA] stands for [Store].[All Stores].[USA]
    assert_lookup( mdx = `[Store].[USA]` kind = `MEMBER` name = `[Store].[USA]` ).
    assert_lookup( mdx = `[Store].[All Stores].[USA]` kind = `MEMBER` name = `[Store].[USA]` ).
    assert_lookup( mdx = `[Store].[USA].[CA]` kind = `MEMBER` name = `[Store].[USA].[CA]` ).
    assert_lookup( mdx = `[Store.Store Id].[1]` kind = `MEMBER` name = `[Store.Store Id].[1]` ).
    assert_lookup( mdx = `[Customers.City].[Seattle]` kind = `MEMBER` name = `[Customers.City].[Seattle]` ).
    " a hierarchy without All member: its root members
    assert_lookup( mdx = `[Time].[1997]` kind = `MEMBER` name = `[Time].[1997]` ).
    assert_lookup( mdx = `[Time].[1997].[Q1]` kind = `MEMBER` name = `[Time].[1997].[Q1]` ).
    assert_lookup( mdx = `[Measures].[Unit Sales]` kind = `MEMBER` name = `[Measures].[Unit Sales]` ).
    assert_lookup( mdx = `[Measures].[Fact Count]` kind = `MEMBER` name = `[Measures].[Fact Count]` ).
    " no dimension prefix needed: the root members of the default hierarchies are searched, in the dimensions' order
    assert_lookup( mdx = `[Unit Sales]` kind = `MEMBER` name = `[Measures].[Unit Sales]` ).
    assert_lookup( mdx = `[USA]` kind = `MEMBER` name = `[Customers].[USA]` ).
    " a name below a level: the first member of the level with the name, on any level (RolapLevel.lookupChild)
    assert_lookup( mdx = `[Store].[Store Country].[USA]` kind = `MEMBER` name = `[Store].[USA]` ).
    assert_lookup( mdx = `[Store].[Store State].[CA]` kind = `MEMBER` name = `[Store].[USA].[CA]` ).
    assert_lookup( mdx = `[Store].[Store City].[Seattle]` kind = `MEMBER` name = `[Store].[USA].[WA].[Seattle]` ).
    " a key segment below a level
    assert_lookup( mdx = `[Store.Store Id].[Store Id].&[1]` kind = `MEMBER` name = `[Store.Store Id].[1]` ).
  ENDMETHOD.

  METHOD not_found.
    assert_lookup( mdx = `[Customers].[Seattle]` kind = `` ).
    assert_lookup( mdx = `[Seattle]` kind = `` ).
    assert_lookup( mdx = `[Store].&[1]` kind = `` ).
    assert_lookup( mdx = `[Store].[Nowhere]` kind = `` ).
    assert_lookup( mdx = `[Nowhere]` kind = `` ).
    assert_lookup( mdx = `[Store].[All Stores].[Nowhere]` kind = `` ).
  ENDMETHOD.

  METHOD case_insensitive.
    assert_lookup( mdx = `[store].[all stores]` kind = `MEMBER` name = `[Store].[All Stores]` ).
  ENDMETHOD.

  METHOD unknown_cube.
    TRY.
        zzxxmla1_cl_mdx_schema_reader=>for_cube( catalog = `` name = `Nowhere` ).
        cl_abap_unit_assert=>fail( `no error` ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( act = error->description exp = `olap4abap Error:MDX cube 'Nowhere' not found` ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

"! Members read by SQL as needed (docs/mvp-scope.md, Member decision), answers of the reference server for ZFMSALES.
CLASS ltc_members DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    DATA reader TYPE REF TO zzxxmla1_cl_mdx_schema_reader.
    METHODS setup RAISING zzxxmla1_cx_xmla.
    METHODS member
      IMPORTING mdx           TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_schema_reader=>ty_member.
    CLASS-METHODS names
      IMPORTING members       TYPE zzxxmla1_cl_mdx_schema_reader=>ty_t_member
      RETURNING VALUE(result) TYPE string_table.
    "! children in hierarchy order, and their number
    METHODS children FOR TESTING.
    "! the parent of a member read alone, without its level
    METHODS parent FOR TESTING.
    "! Lag and Lead along a level across parents; the empty member (SID 0) comes first
    METHODS lead FOR TESTING.
    "! a range across parents, given either way round
    METHODS range FOR TESTING.
    "! members by their paths, in hierarchy order; a path without member left out
    METHODS by_paths FOR TESTING.
ENDCLASS.

CLASS ltc_members IMPLEMENTATION.

  METHOD setup.
    reader = zzxxmla1_cl_mdx_schema_reader=>for_cube( catalog = `` name = `ZFMSALES` ).
  ENDMETHOD.

  METHOD member.
    TRY.
        result = reader->lookup_compound( segments = zzxxmla1_cl_mdx_parser=>parse_expression( mdx )->segments
                                          category = zzxxmla1_cl_mdx_type=>c_category-member )-member.
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>fail( error->description ).
    ENDTRY.
    cl_abap_unit_assert=>assert_not_initial( act = result msg = mdx ).
  ENDMETHOD.

  METHOD names.
    result = VALUE #( FOR m IN members ( m-unique_name ) ).
  ENDMETHOD.

  METHOD children.
    cl_abap_unit_assert=>assert_equals(
      act = names( reader->get_member_children( member( `[Store].[USA].[CA]` ) ) )
      exp = VALUE string_table( ( `[Store].[USA].[CA].[Alameda]` ) ( `[Store].[USA].[CA].[Beverly Hills]` )
                                ( `[Store].[USA].[CA].[Los Angeles]` ) ( `[Store].[USA].[CA].[San Diego]` )
                                ( `[Store].[USA].[CA].[San Francisco]` ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = names( reader->get_member_children( member( `[Store].[All Stores]` ) ) )
      exp = VALUE string_table( ( `[Store].[Canada]` ) ( `[Store].[Mexico]` ) ( `[Store].[USA]` ) ) ).
    " counted without reading the children
    cl_abap_unit_assert=>assert_equals( act = reader->get_children_count( member( `[Store].[USA]` ) ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = reader->get_children_count( member( `[Store].[All Stores]` ) ) exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = reader->get_children_count( member( `[Store].[USA].[CA]` ) ) exp = 5 ).
  ENDMETHOD.

  METHOD parent.
    cl_abap_unit_assert=>assert_equals(
      act = reader->get_parent_member( member( `[Store].[USA].[CA].[Alameda]` ) )-unique_name
      exp = `[Store].[USA].[CA]` ).
    cl_abap_unit_assert=>assert_equals( act = reader->get_parent_member( member( `[Store].[USA]` ) )-unique_name
                                        exp = `[Store].[All Stores]` ).
    cl_abap_unit_assert=>assert_initial( reader->get_parent_member( member( `[Store].[All Stores]` ) ) ).
  ENDMETHOD.

  METHOD lead.
    DATA(q1) = member( `[Time].[1997].[Q1]` ).
    cl_abap_unit_assert=>assert_equals( act = reader->get_lead_member( member = member( `[Time].[1997].[Q4]` ) n = 1 )-unique_name
                                        exp = `[Time].[1998].[Q1]` ).
    cl_abap_unit_assert=>assert_equals( act = reader->get_lead_member( member = q1 n = 5 )-unique_name
                                        exp = `[Time].[1998].[Q2]` ).
    cl_abap_unit_assert=>assert_equals( act = reader->get_lead_member( member = q1 n = -1 )-unique_name
                                        exp = `[Time].[0].[]` ).
    cl_abap_unit_assert=>assert_initial( reader->get_lead_member( member = q1 n = -2 ) ).
    cl_abap_unit_assert=>assert_equals( act = reader->get_lead_member( member = q1 n = 0 ) exp = q1 ).
  ENDMETHOD.

  METHOD range.
    DATA(expected) = VALUE string_table( ( `[Time].[1997].[Q3]` ) ( `[Time].[1997].[Q4]` ) ( `[Time].[1998].[Q1]` )
                                         ( `[Time].[1998].[Q2]` ) ).
    DATA(q3) = member( `[Time].[1997].[Q3]` ).
    DATA(q2) = member( `[Time].[1998].[Q2]` ).
    cl_abap_unit_assert=>assert_equals( act = names( reader->get_member_range( member1 = q3 member2 = q2 ) )
                                        exp = expected ).
    cl_abap_unit_assert=>assert_equals( act = names( reader->get_member_range( member1 = q2 member2 = q3 ) )
                                        exp = expected ).
  ENDMETHOD.

  METHOD by_paths.
    DATA(sf) = member( `[Store].[USA].[CA].[San Francisco]` ).
    DATA(alameda) = member( `[Store].[USA].[CA].[Alameda]` ).
    DATA(level) = sf-level.
    " a new reader: nothing read yet
    TRY.
        reader = zzxxmla1_cl_mdx_schema_reader=>for_cube( catalog = `` name = `ZFMSALES` ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>fail( error->description ).
    ENDTRY.
    cl_abap_unit_assert=>assert_equals(
      act = names( reader->get_members_by_paths( level = level
                                                 paths = VALUE #( ( sf-path ) ( |nowhere{ zzxxmla1_cl_model=>c_separator }x| )
                                                                  ( alameda-path ) ( sf-path ) ) ) )
      exp = VALUE string_table( ( `[Store].[USA].[CA].[Alameda]` ) ( `[Store].[USA].[CA].[San Francisco]` ) ) ).
  ENDMETHOD.

ENDCLASS.

"! BW's names on the clinic demo's aDSO (ZZXXMLA1_SETUP, catalog and cube ZCLVISITA, docs/next-steps.md, Next: BW's
"! MDX on InfoProviders): the names of the statements the probe asks BW (reference/auth/statements.json) looked up to
"! olap4abap's elements.
CLASS ltc_bw_names DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    CLASS-DATA reader TYPE REF TO zzxxmla1_cl_mdx_schema_reader.
    CLASS-METHODS class_setup RAISING zzxxmla1_cx_xmla.
    "! BW's name of a BW hierarchy: characteristic, name and version in columns of 30 characters.
    CLASS-METHODS hierarchy
      IMPORTING characteristic TYPE string
                !name          TYPE string
                !version       TYPE string OPTIONAL
      RETURNING VALUE(result)  TYPE string.
    "! BW's name of a node: its name in 32 characters and its InfoObject in 30.
    CLASS-METHODS node
      IMPORTING !name         TYPE string
                iobj          TYPE string DEFAULT `0HIER_NODE`
      RETURNING VALUE(result) TYPE string.
    "! The element the identifier (its segments in brackets) names: its kind and its unique name (a member's is matched
    "! as a pattern, CP).
    METHODS assert_lookup
      IMPORTING segments TYPE string_table
                kind     TYPE string
                !name    TYPE string OPTIONAL.
    METHODS split_hierarchy_name FOR TESTING.
    METHODS split_member_name FOR TESTING.
    METHODS characteristics FOR TESTING.
    METHODS bw_hierarchies FOR TESTING.
    METHODS levels FOR TESTING.
    METHODS nodes_and_leaves FOR TESTING.
    METHODS not_found FOR TESTING.
    METHODS unknown_cube FOR TESTING.
ENDCLASS.

CLASS ltc_bw_names IMPLEMENTATION.

  METHOD class_setup.
    reader = zzxxmla1_cl_mdx_schema_reader=>for_bw_cube( `$ZCLVISITA` ).
  ENDMETHOD.

  METHOD hierarchy.
    result = |{ characteristic WIDTH = 30 }{ name WIDTH = 30 }{ version }|.
  ENDMETHOD.

  METHOD node.
    result = |{ name WIDTH = 32 }{ iobj WIDTH = 30 }|.
  ENDMETHOD.

  METHOD assert_lookup.
    DATA(mdx) = concat_lines_of( table = VALUE string_table( FOR s IN segments ( |[{ s }]| ) ) sep = `.` ).
    TRY.
        DATA(id) = zzxxmla1_cl_mdx_parser=>parse_expression( mdx ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>fail( error->description ).
    ENDTRY.
    DATA(element) = reader->lookup_compound( id->segments ).
    cl_abap_unit_assert=>assert_equals( act = element-kind exp = kind msg = mdx ).
    CASE kind.
      WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-member.
        cl_abap_unit_assert=>assert_true( act = xsdbool( element-member-unique_name CP name )
                                          msg = |{ mdx }: { element-member-unique_name }| ).
      WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-dimension.
        cl_abap_unit_assert=>assert_equals( act = reader->get_dimension( element-id )-unique_name exp = name msg = mdx ).
      WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-hierarchy.
        cl_abap_unit_assert=>assert_equals( act = reader->get_hierarchy( element-id )-unique_name exp = name msg = mdx ).
      WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-level.
        cl_abap_unit_assert=>assert_equals( act = reader->get_level( element-id )-unique_name exp = name msg = mdx ).
    ENDCASE.
  ENDMETHOD.

  METHOD split_hierarchy_name.
    zzxxmla1_cl_mdx_schema_reader=>bw_hierarchy_name(
      EXPORTING name           = hierarchy( characteristic = `ZCLDOC` name = `ZCLDOC_ORG` version = `001` )
      IMPORTING characteristic = DATA(characteristic)
                hierarchy      = DATA(name)
                version        = DATA(version) ).
    cl_abap_unit_assert=>assert_equals( act = characteristic exp = `ZCLDOC` ).
    cl_abap_unit_assert=>assert_equals( act = name exp = `ZCLDOC_ORG` ).
    cl_abap_unit_assert=>assert_equals( act = version exp = `001` ).
    " not version dependent: no version
    zzxxmla1_cl_mdx_schema_reader=>bw_hierarchy_name(
      EXPORTING name           = hierarchy( characteristic = `ZCLDIAG` name = `ZCLDIAG_ICD` )
      IMPORTING characteristic = characteristic
                hierarchy      = name
                version        = version ).
    cl_abap_unit_assert=>assert_equals( act = characteristic exp = `ZCLDIAG` ).
    cl_abap_unit_assert=>assert_equals( act = name exp = `ZCLDIAG_ICD` ).
    cl_abap_unit_assert=>assert_initial( version ).
    " one word: a characteristic, no BW hierarchy
    zzxxmla1_cl_mdx_schema_reader=>bw_hierarchy_name(
      EXPORTING name           = `ZCLDIAG`
      IMPORTING characteristic = characteristic
                hierarchy      = name
                version        = version ).
    cl_abap_unit_assert=>assert_initial( characteristic ).
    cl_abap_unit_assert=>assert_initial( name ).
  ENDMETHOD.

  METHOD split_member_name.
    zzxxmla1_cl_mdx_schema_reader=>bw_member_name( EXPORTING name      = node( `CARD` )
                                                   IMPORTING node_name = DATA(node_name)
                                                             iobj      = DATA(iobj) ).
    cl_abap_unit_assert=>assert_equals( act = node_name exp = `CARD` ).
    cl_abap_unit_assert=>assert_equals( act = iobj exp = `0HIER_NODE` ).
    " a name of all 32 characters runs into the InfoObject
    zzxxmla1_cl_mdx_schema_reader=>bw_member_name( EXPORTING name      = node( `CHRONIC_LOWER_RESPIRATORY_DISEAS` )
                                                   IMPORTING node_name = node_name
                                                             iobj      = iobj ).
    cl_abap_unit_assert=>assert_equals( act = node_name exp = `CHRONIC_LOWER_RESPIRATORY_DISEAS` ).
    cl_abap_unit_assert=>assert_equals( act = iobj exp = `0HIER_NODE` ).
    " a leaf: its key, the initial value too
    zzxxmla1_cl_mdx_schema_reader=>bw_member_name( EXPORTING name      = `A09`
                                                   IMPORTING node_name = node_name
                                                             iobj      = iobj ).
    cl_abap_unit_assert=>assert_equals( act = node_name exp = `A09` ).
    cl_abap_unit_assert=>assert_initial( iobj ).
    zzxxmla1_cl_mdx_schema_reader=>bw_member_name( EXPORTING name      = ``
                                                   IMPORTING node_name = node_name
                                                             iobj      = iobj ).
    cl_abap_unit_assert=>assert_initial( node_name ).
    cl_abap_unit_assert=>assert_initial( iobj ).
  ENDMETHOD.

  METHOD characteristics.
    assert_lookup( segments = VALUE #( ( `Measures` ) ) kind = `DIMENSION` name = `[Measures]` ).
    assert_lookup( segments = VALUE #( ( `Measures` ) ( `ZCLVISNO` ) ) kind = `MEMBER` name = `[Measures].[ZCLVISNO]` ).
    " a characteristic is its flat hierarchy, a value its key (NUMC with its zeros)
    assert_lookup( segments = VALUE #( ( `ZCLDOC` ) ) kind = `HIERARCHY` name = `[ZCLDOC]` ).
    assert_lookup( segments = VALUE #( ( `ZCLDIAG` ) ) kind = `HIERARCHY` name = `[ZCLDIAG]` ).
    assert_lookup( segments = VALUE #( ( `ZCLDOC` ) ( `001` ) ) kind = `MEMBER` name = `[ZCLDOC].[001]` ).
    assert_lookup( segments = VALUE #( ( `ZCLDIAG` ) ( `A09` ) ) kind = `MEMBER` name = `[ZCLDIAG].[A09]` ).
  ENDMETHOD.

  METHOD bw_hierarchies.
    assert_lookup( segments = VALUE #( ( hierarchy( characteristic = `ZCLDIAG` name = `ZCLDIAG_ICD` ) ) )
                   kind     = `HIERARCHY`
                   name     = `[ZCLDIAG.ZCLDIAG_ICD]` ).
    " version dependent: one hierarchy per version
    assert_lookup( segments = VALUE #( ( hierarchy( characteristic = `ZCLDOC` name = `ZCLDOC_ORG` version = `001` ) ) )
                   kind     = `HIERARCHY`
                   name     = `[ZCLDOC.ZCLDOC_ORG_001]` ).
    assert_lookup( segments = VALUE #( ( hierarchy( characteristic = `ZCLDOC` name = `ZCLDOC_SITE` version = `002` ) ) )
                   kind     = `HIERARCHY`
                   name     = `[ZCLDOC.ZCLDOC_SITE_002]` ).
  ENDMETHOD.

  METHOD levels.
    " LEVEL00 is the All level
    assert_lookup( segments = VALUE #( ( `ZCLDIAG` ) ( `LEVEL00` ) ) kind = `LEVEL` name = `[ZCLDIAG].[(All)]` ).
    DATA(icd) = hierarchy( characteristic = `ZCLDIAG` name = `ZCLDIAG_ICD` ).
    assert_lookup( segments = VALUE #( ( icd ) ( `LEVEL00` ) ) kind = `LEVEL` name = `[ZCLDIAG.ZCLDIAG_ICD].[(All)]` ).
    assert_lookup( segments = VALUE #( ( icd ) ( `LEVEL02` ) ) kind = `LEVEL` name = `[ZCLDIAG.ZCLDIAG_ICD].[Level 02]` ).
  ENDMETHOD.

  METHOD nodes_and_leaves.
    DATA(icd) = hierarchy( characteristic = `ZCLDIAG` name = `ZCLDIAG_ICD` ).
    assert_lookup( segments = VALUE #( ( icd ) ( node( `RESPIRATORY` ) ) )
                   kind     = `MEMBER`
                   name     = `[ZCLDIAG.ZCLDIAG_ICD].[Level 02].&[0HIER_NODE]&[DIAGNOSES]&[0HIER_NODE]&[RESPIRATORY]` ).
    assert_lookup( segments = VALUE #( ( icd ) ( node( `CHRONIC_LOWER_RESPIRATORY_DISEAS` ) ) )
                   kind     = `MEMBER`
                   name     = `*&[0HIER_NODE]&[CHRONIC_LOWER_RESPIRATORY_DISEAS]` ).
    " a leaf by its key; the initial value is a leaf under NO_DIAGNOSIS
    assert_lookup( segments = VALUE #( ( icd ) ( `A09` ) ) kind = `MEMBER` name = `*&[ZCLDIAG]&[A09]` ).
    assert_lookup( segments = VALUE #( ( icd ) ( `` ) ) kind = `MEMBER` name = `*&[NO_DIAGNOSIS]&[ZCLDIAG]&[]` ).
    DATA(org) = hierarchy( characteristic = `ZCLDOC` name = `ZCLDOC_ORG` version = `001` ).
    assert_lookup( segments = VALUE #( ( org ) ( node( `CARD` ) ) ) kind = `MEMBER` name = `*&[0HIER_NODE]&[CARD]` ).
    assert_lookup( segments = VALUE #( ( org ) ( `001` ) ) kind = `MEMBER` name = `*&[ZCLDOC]&[001]` ).
  ENDMETHOD.

  METHOD not_found.
    " olap4abap's names are not BW's
    assert_lookup( segments = VALUE #( ( `ZCLDIAG.ZCLDIAG_ICD` ) ) kind = `` ).
    assert_lookup( segments = VALUE #( ( hierarchy( characteristic = `ZCLDIAG` name = `ZCLDIAG_ICD` ) ) ( `Level 02` ) )
                   kind     = `` ).
    assert_lookup( segments = VALUE #( ( hierarchy( characteristic = `ZCLDIAG` name = `NOWHERE` ) ) ) kind = `` ).
    assert_lookup( segments = VALUE #( ( hierarchy( characteristic = `ZCLDIAG` name = `ZCLDIAG_ICD` ) )
                                       ( node( `NOWHERE` ) ) )
                   kind     = `` ).
    assert_lookup( segments = VALUE #( ( `ZCLDOC` ) ( `999` ) ) kind = `` ).
  ENDMETHOD.

  METHOD unknown_cube.
    TRY.
        zzxxmla1_cl_mdx_schema_reader=>for_bw_cube( `$NOWHERE` ).
        cl_abap_unit_assert=>fail( `no error` ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( act = error->description
                                            exp = `olap4abap Error:MDX cube '$NOWHERE' not found` ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
