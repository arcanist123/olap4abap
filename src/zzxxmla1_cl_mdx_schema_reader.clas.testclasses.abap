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