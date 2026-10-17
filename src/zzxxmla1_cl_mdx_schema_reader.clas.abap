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
"! The schema reader of a cube: the port of SchemaReader (RolapSchemaReader) and of the element classes it
"! navigates (CubeBase/RolapCube, DimensionBase, HierarchyBase, LevelBase, MemberBase), over the model of the cube
"! (ZZXXMLA1_CL_MODEL). The cube has the Measures dimension (id 0, one hierarchy without All, level MeasuresLevel whose
"! members are the measures) and one dimension per model dimension; a model hierarchy (id = its position in the model,
"! from 1) has the (All) level with the All member if it has one, then its levels, whose members are read from the
"! dimension table as a tree (ZZXXMLA1_CL_MODEL=>MEMBERS) in hierarchy order.
"! Names compare as the reference compares them with olap.case.sensitive=false and SsasCompatibleNaming=false:
"! case-insensitive, except hierarchy names at cube level (CubeBase.lookupHierarchy uses equals).
CLASS zzxxmla1_cl_mdx_schema_reader DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    INTERFACES zzxxmla1_if_mdx_schema_reader.
    ALIASES get_hierarchies FOR zzxxmla1_if_mdx_schema_reader~get_hierarchies.
    ALIASES get_default_member FOR zzxxmla1_if_mdx_schema_reader~get_default_member.
    ALIASES measure_member FOR zzxxmla1_if_mdx_schema_reader~measure_member.
    ALIASES get_calculation FOR zzxxmla1_if_mdx_schema_reader~get_calculation.
    ALIASES get_measures FOR zzxxmla1_if_mdx_schema_reader~get_measures.
    TYPES ty_t_id TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_member,
        hierarchy     TYPE string,   " unique name of the hierarchy
        hier_id       TYPE i,        " id of the hierarchy: 0 for Measures, else the position in the model
        measure_index TYPE i,        " position in the measures (Measures hierarchy only)
        order_key     TYPE string,   " hierarchy order (ZZXXMLA1_CL_MODEL, ty_member-order_key); the All member empty
        key           TYPE string,   " value of the level column; empty for the All member
        key_level     TYPE i,        " the level in the model (1 the first below the All level), 0: the All member
        path          TYPE string,   " the keys of the model levels down to key_level (ZZXXMLA1_CL_MODEL)
        unique_name   TYPE string,
        name          TYPE string,   " the name its unique name ends with (Member.getName)
        caption       TYPE string,
        level         TYPE i,        " id of the level
        level_name    TYPE string,   " unique name of the level
        level_number  TYPE i,
        parent_unique TYPE string,
        children      TYPE i,
        display_info  TYPE i,
        calculated    TYPE abap_bool, " a calculated member of the query (RolapCalculatedMember)
        solve_order   TYPE i,         " calculated members: SOLVE_ORDER, else 0
        is_null       TYPE abap_bool, " the null member of the hierarchy (RolapHierarchy.getNullMember)
        "! a member made while the query runs (VisualTotalMember) has the unique name of the member it stands for: the
        "! key of its calculation (get_calculation); empty for any other member
        calc_name     TYPE string,
      END OF ty_member,
      ty_t_member TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY.
    TYPES:
      "! A calculated member of the query with its formula (Formula): the resolved expression, the format expression
      "! (FORMAT_EXP_PARSED, if any) and whether the expression calls Aggregate (containsAggregateFunction). The
      "! placeholder of a compound slicer (RolapResult.CompoundSlicerRolapMember) has a calculation of its own
      "! (getCompiledExpression, kept by the root evaluator) instead of an expression, and is not calculated in the query
      "! (cube scope).
      BEGIN OF ty_calculated_member,
        member             TYPE ty_member,
        expression         TYPE REF TO zzxxmla1_cl_mdx_node,
        format_expression  TYPE REF TO zzxxmla1_cl_mdx_node,
        contains_aggregate TYPE abap_bool,
        cube_scope         TYPE abap_bool,
      END OF ty_calculated_member,
      ty_t_calculated_member TYPE STANDARD TABLE OF ty_calculated_member WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_dimension,
        id          TYPE i,
        name        TYPE string,
        unique_name TYPE string,
        is_measures TYPE abap_bool,
        hierarchies TYPE ty_t_id,    " the first one is the default hierarchy
        type        TYPE string,     " DimensionType: StandardDimension, TimeDimension or MeasuresDimension
      END OF ty_dimension,
      ty_t_dimension TYPE STANDARD TABLE OF ty_dimension WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_hierarchy,
        id              TYPE i,
        dimension       TYPE i,
        name            TYPE string,   " Measures, or dimension.hierarchy as version 3 schemas name them
        unique_name     TYPE string,
        has_all         TYPE abap_bool,
        all_member_name TYPE string,
        levels          TYPE ty_t_id,
        model           TYPE zzxxmla1_cl_model=>ty_hierarchy,
      END OF ty_hierarchy,
      ty_t_hierarchy TYPE STANDARD TABLE OF ty_hierarchy WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_level,
        id          TYPE i,
        hierarchy   TYPE i,
        depth       TYPE i,
        name        TYPE string,
        unique_name TYPE string,
        is_all      TYPE abap_bool,
        key_level   TYPE i,          " the level in the model, from 1; 0 for the (All) level
        type        TYPE string,     " LevelType: Regular (also (All) and Measures), TimeYears, TimeMonths, ...
      END OF ty_level,
      ty_t_level TYPE STANDARD TABLE OF ty_level WITH EMPTY KEY.
    TYPES:
      "! An OLAP element (OlapElement): kind CUBE, DIMENSION, HIERARCHY, LEVEL or MEMBER, the id of the dimension,
      "! hierarchy or level, or the member; an initial kind is no element (null).
      BEGIN OF ty_element,
        kind   TYPE string,
        id     TYPE i,
        member TYPE ty_member,
      END OF ty_element.
    CONSTANTS:
      BEGIN OF c_element,
        cube      TYPE string VALUE `CUBE`,
        dimension TYPE string VALUE `DIMENSION`,
        hierarchy TYPE string VALUE `HIERARCHY`,
        level     TYPE string VALUE `LEVEL`,
        member    TYPE string VALUE `MEMBER`,
      END OF c_element.
    CONSTANTS c_measures TYPE i VALUE 0.

    DATA cube     TYPE zzxxmla1_cl_schema=>ty_cube READ-ONLY.
    DATA measures TYPE zzxxmla1_cl_model=>ty_t_measure READ-ONLY.

    "! The schema reader of the cube with the name (case-insensitive) in the catalog (empty: any); MdxCubeNotFound if
    "! there is none.
    CLASS-METHODS for_cube
      IMPORTING catalog       TYPE string
                name          TYPE string
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_schema_reader
      RAISING   zzxxmla1_cx_xmla.

    METHODS get_dimensions RETURNING VALUE(result) TYPE ty_t_dimension.
    "! The model hierarchies (without Measures) in model order, as ZZXXMLA1_CL_MODEL=>HIERARCHIES gives them.
    METHODS get_model_hierarchies RETURNING VALUE(result) TYPE zzxxmla1_cl_model=>ty_t_hierarchy.
    METHODS get_dimension
      IMPORTING id            TYPE i
      RETURNING VALUE(result) TYPE ty_dimension.
    METHODS get_hierarchy
      IMPORTING id            TYPE i
      RETURNING VALUE(result) TYPE ty_hierarchy.
    METHODS get_level
      IMPORTING id            TYPE i
      RETURNING VALUE(result) TYPE ty_level.
    "! The members of a hierarchy in hierarchy order (the All member first): every level read whole. Only for a query
    "! that asks for all of them (Hierarchy.Members).
    METHODS get_hierarchy_members
      IMPORTING hierarchy     TYPE i
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The members of a level in hierarchy order, read whole (once). Only for a query that asks for all of them.
    METHODS get_level_members
      IMPORTING level         TYPE i
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The members of a level in hierarchy order whose rows hold a condition (SQL on the columns of the hierarchy's
    "! member table, ZZXXMLA1_CL_MODEL=>READ_MEMBERS), below an ancestor if one is given: one query (a Filter by the
    "! labels of the members, read as SqlMemberSource reads a level with a constraint).
    METHODS get_level_members_where
      IMPORTING level         TYPE i
                !condition    TYPE string
                ancestor      TYPE ty_member OPTIONAL
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The members of the first level of a hierarchy: its All member, without one the first level read whole.
    METHODS get_hierarchy_root_members
      IMPORTING hierarchy     TYPE i
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The children of a member in hierarchy order (SqlMemberSource.getMemberChildren), read once.
    METHODS get_member_children
      IMPORTING member        TYPE ty_member
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The All member of a hierarchy; initial if it has none.
    METHODS get_all_member
      IMPORTING hierarchy     TYPE i
      RETURNING VALUE(result) TYPE ty_member.
    "! The stored members of a level with the paths (the keys from the first level, ZZXXMLA1_CL_MODEL), in hierarchy
    "! order; a path without member is left out. The paths are ones with facts (read from the facts by the caller), so
    "! the members are read without the restriction to the members with facts. Those not read yet are read in one
    "! query per ZZXXMLA1_CL_MODEL=>C_MAX_CONSTRAINTS paths, or with the whole level if they are more than one query's
    "! and more than half of the level.
    METHODS get_members_by_paths
      IMPORTING level         TYPE i
                paths         TYPE string_table
      RETURNING VALUE(result) TYPE ty_t_member.
    "! SmartMemberReader.getLeadMember: the member n positions after the member in its level (before it if n is
    "! negative), across parents, in hierarchy order; initial if there is none. One query (LIMIT 1 OFFSET n - 1).
    METHODS get_lead_member
      IMPORTING member        TYPE ty_member
                n             TYPE int8
      RETURNING VALUE(result) TYPE ty_member.
    "! SmartMemberReader.getMemberRange: the members of the level of two members from the one that comes first to the
    "! other, in hierarchy order, across parents. One query.
    METHODS get_member_range
      IMPORTING member1       TYPE ty_member
                member2       TYPE ty_member
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The number of children of a stored member (Property CHILDREN_CARDINALITY, the XMLA DisplayInfo); counted in
    "! one query with the ones of the members of its level that prefetch_children_counts was given.
    METHODS get_children_count
      IMPORTING member        TYPE ty_member
      RETURNING VALUE(result) TYPE i.
    "! Counts the children of the stored members in one query per level (and ZZXXMLA1_CL_MODEL=>C_MAX_CONSTRAINTS
    "! members), for get_children_count.
    METHODS prefetch_children_counts
      IMPORTING members TYPE ty_t_member.
    "! The id of the level of a hierarchy at a level of the model (from 1).
    METHODS get_level_of
      IMPORTING hierarchy     TYPE i
                key_level     TYPE i
      RETURNING VALUE(result) TYPE i.
    "! The number of members of a level (SqlMemberSource.getLevelMemberCount, ZZXXMLA1_CL_MODEL=>LEVEL_CARDINALITY),
    "! counted once; 1 for the (All) level, the measures for the measures' level.
    METHODS get_level_cardinality
      IMPORTING level         TYPE i
      RETURNING VALUE(result) TYPE i.
    "! SchemaReader.getElementChild: OlapElement.lookupChild of the parent.
    METHODS get_element_child
      IMPORTING parent        TYPE ty_element
                segment       TYPE zzxxmla1_cl_mdx_node=>ty_segment
      RETURNING VALUE(result) TYPE ty_element.
    METHODS lookup_member_child_by_name
      IMPORTING member        TYPE ty_member
                name          TYPE string
      RETURNING VALUE(result) TYPE ty_element.
    "! Util.lookupCompound with the cube as parent and failIfNotFound false: the element named by the segments, as
    "! category (zzxxmla1_cl_mdx_type=>c_category: unknown, dimension, hierarchy, level or member), or none.
    METHODS lookup_compound
      IMPORTING segments      TYPE zzxxmla1_cl_mdx_node=>ty_t_segment
                category      TYPE i DEFAULT 0
      RETURNING VALUE(result) TYPE ty_element.
    "! The dimension of a hierarchy.
    METHODS dimension_of
      IMPORTING hierarchy     TYPE i
      RETURNING VALUE(result) TYPE i.
    "! DimensionType.getHierarchy: the only hierarchy of the dimension, else the one named like the dimension
    "! (getHierarchyWithDefaultName); -1 if there is none, or for no dimension (-1).
    METHODS get_dimension_hierarchy
      IMPORTING dimension     TYPE i
      RETURNING VALUE(result) TYPE i.
    "! Defines a calculated member of the query (Query.QuerySchemaReader: the members of the formulas).
    METHODS add_calculated_member
      IMPORTING member TYPE ty_member.
    "! The calculated member of the query with the unique name, with its formula; initial if there is none.
    METHODS get_calculated_member
      IMPORTING unique_name   TYPE string
      RETURNING VALUE(result) TYPE ty_calculated_member.
    "! Sets the formula of a calculated member (the member's unique name identifies it).
    METHODS set_calculated_member
      IMPORTING calculated TYPE ty_calculated_member.
    "! SchemaReader.getCalculatedMembers(hierarchy): the calculated members of the query in the hierarchy.
    "! A calculated member made while the query runs (VisualTotalMember), found by its calc_name, not by its unique
    "! name, and not one of the query's calculated members (get_calculated_members).
    METHODS add_visual_total
      IMPORTING calculated TYPE ty_calculated_member.
    METHODS get_calculated_members
      IMPORTING hierarchy     TYPE i
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The parent member of a member; initial for a member of the first level.
    METHODS get_parent_member
      IMPORTING member        TYPE ty_member
      RETURNING VALUE(result) TYPE ty_member.
    "! RolapCube.getTimeHierarchy: the first hierarchy of a time dimension; -1 if there is none.
    METHODS get_time_hierarchy
      RETURNING VALUE(result) TYPE i.
    "! CubeBase.getTimeLevel: the first level of the level type in the hierarchies of the time dimensions; 0 if there
    "! is none.
    METHODS get_time_level
      IMPORTING level_type    TYPE string
      RETURNING VALUE(result) TYPE i.
    "! RolapLevel.getProperties: the member properties of a level, its own; none for an (All) level and Measures.
    METHODS get_level_properties
      IMPORTING level         TYPE i
      RETURNING VALUE(result) TYPE zzxxmla1_cl_schema=>ty_t_property.
    "! Util.lookupProperty without the standard properties: the member property with the name (case-sensitive) of the
    "! level or of a level above it; initial if there is none.
    METHODS lookup_level_property
      IMPORTING level         TYPE i
                name          TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_cl_schema=>ty_property.
    "! Util.isValidProperty: a member property of the level or of a level above it (case-sensitive), or a standard
    "! member property (Property.lookup, case-insensitive, isMemberProperty and isStandard).
    METHODS is_valid_property
      IMPORTING level         TYPE i
                name          TYPE string
      RETURNING VALUE(result) TYPE abap_bool.
    "! RolapMemberBase.getPropertyFromMap with matchCase false: the value of a member property of the member's level,
    "! the name compared case-insensitively, as read with the member; found is false if its level has no such property.
    METHODS get_property_value
      IMPORTING member   TYPE ty_member
                name     TYPE string
      EXPORTING property TYPE zzxxmla1_cl_schema=>ty_property
                value    TYPE string
                found    TYPE abap_bool.

  PRIVATE SECTION.
    TYPES:
      "! a stored member read (MemberCache), by its hierarchy, level in the model and path, with the values of its
      "! level's member properties in their order
      BEGIN OF ty_cached,
        hier_id    TYPE i,
        key_level  TYPE i,
        path       TYPE string,
        member     TYPE ty_member,
        properties TYPE string_table,
      END OF ty_cached.
    TYPES:
      "! a stored member by its unique name (the first one read with it): to find a calculated member's parent
      BEGIN OF ty_named,
        hier_id     TYPE i,
        unique_name TYPE string,
        key_level   TYPE i,
        path        TYPE string,
      END OF ty_named.
    TYPES:
      "! the children of a member (by its hierarchy, level in the model and path; the All member is level 0) in
      "! hierarchy order
      BEGIN OF ty_children,
        hier_id   TYPE i,
        key_level TYPE i,
        path      TYPE string,
        members   TYPE ty_t_member,
      END OF ty_children.
    TYPES:
      BEGIN OF ty_level_members,
        level   TYPE i,
        members TYPE ty_t_member,
      END OF ty_level_members.
    TYPES:
      "! the members a query of read gave, by its parameters
      BEGIN OF ty_query,
        key     TYPE string,
        members TYPE ty_t_member,
      END OF ty_query.
    TYPES:
      BEGIN OF ty_level_count,
        level TYPE i,
        count TYPE i,
      END OF ty_level_count.
    TYPES:
      BEGIN OF ty_children_count,
        hier_id   TYPE i,
        key_level TYPE i,
        path      TYPE string,
        count     TYPE i,
      END OF ty_children_count.
    TYPES:
      BEGIN OF ty_default_member,
        hierarchy TYPE i,
        member    TYPE ty_member,
      END OF ty_default_member.
    DATA dimensions        TYPE ty_t_dimension.
    DATA hierarchies       TYPE ty_t_hierarchy.
    DATA levels            TYPE ty_t_level.
    DATA model_hierarchies TYPE zzxxmla1_cl_model=>ty_t_hierarchy.
    DATA cached            TYPE HASHED TABLE OF ty_cached WITH UNIQUE KEY hier_id key_level path.
    DATA named             TYPE HASHED TABLE OF ty_named WITH UNIQUE KEY hier_id unique_name.
    DATA children_lists    TYPE HASHED TABLE OF ty_children WITH UNIQUE KEY hier_id key_level path.
    DATA level_lists       TYPE HASHED TABLE OF ty_level_members WITH UNIQUE KEY level.
    DATA level_counts      TYPE HASHED TABLE OF ty_level_count WITH UNIQUE KEY level.
    DATA queries           TYPE HASHED TABLE OF ty_query WITH UNIQUE KEY key.
    DATA children_counts   TYPE HASHED TABLE OF ty_children_count WITH UNIQUE KEY hier_id key_level path.
    DATA default_members   TYPE HASHED TABLE OF ty_default_member WITH UNIQUE KEY hierarchy.
    DATA calculated_members TYPE ty_t_calculated_member.
    DATA visual_totals TYPE ty_t_calculated_member.

    METHODS build
      RAISING zzxxmla1_cx_xmla.
    "! Reads members of a level of a hierarchy (ZZXXMLA1_CL_MODEL=>READ_MEMBERS) and keeps them: a member read before
    "! is the one kept.
    "! @parameter level_no | the level in the model, from 1
    "! with_facts: the condition selects members with facts only, so the members are read from the dimension table
    "! without the restriction to the members with facts (ZZXXMLA1_CL_MODEL=>MEMBER_TABLE)
    METHODS read
      IMPORTING hierarchy     TYPE i
                level_no      TYPE i
                !condition    TYPE string OPTIONAL
                descending    TYPE abap_bool DEFAULT abap_false
                !limit        TYPE i DEFAULT 0
                !offset       TYPE i DEFAULT 0
                with_facts    TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result) TYPE ty_t_member.
    "! Keeps a member read from the model (a member read before is the one kept) and gives it.
    METHODS remember
      IMPORTING hierarchy     TYPE i
                model_member  TYPE zzxxmla1_cl_model=>ty_member
      RETURNING VALUE(result) TYPE ty_member.
    "! The id of the level of a hierarchy at a level of the model (from 1).
    METHODS level_of
      IMPORTING hierarchy     TYPE i
                level_no      TYPE i
      RETURNING VALUE(result) TYPE i.
    "! A stored member read before, by its level in the model and path; initial if none.
    METHODS cached_member
      IMPORTING hierarchy     TYPE i
                key_level     TYPE i
                !path         TYPE string
      RETURNING VALUE(result) TYPE ty_member.
    "! The first member of a level with a name (compared as names are), in hierarchy order; below a member (its
    "! children) if one is given.
    METHODS member_by_name
      IMPORTING level         TYPE i
                name          TYPE string
                parent        TYPE ty_member OPTIONAL
      RETURNING VALUE(result) TYPE ty_member.
    "! The All member of a hierarchy that has one, made without reading members (RolapHierarchy.init). Its children
    "! are not counted: set_display_info counts them with get_member_children.
    METHODS all_member
      IMPORTING hierarchy     TYPE i
      RETURNING VALUE(result) TYPE ty_member.
    "! Resolves the defaultMember of a hierarchy (Util.parseIdentifier and getMemberByUniqueName).
    METHODS resolve_default_member
      IMPORTING hierarchy     TYPE i
      RETURNING VALUE(result) TYPE ty_member
      RAISING   zzxxmla1_cx_xmla.
    "! QuerySchemaReader.getCalculatedMember: the calculated member of the query the names match (Util.matches).
    METHODS lookup_calculated_member
      IMPORTING segments      TYPE zzxxmla1_cl_mdx_node=>ty_t_segment
      RETURNING VALUE(result) TYPE ty_element.
    "! Util.matches(member, nameParts).
    METHODS matches
      IMPORTING member        TYPE ty_member
                segments      TYPE zzxxmla1_cl_mdx_node=>ty_t_segment
      RETURNING VALUE(result) TYPE abap_bool.
    "! Id.Segment.matches(name): a quoted or unquoted name compares case-insensitively, a key never matches.
    CLASS-METHODS segment_matches
      IMPORTING segment       TYPE zzxxmla1_cl_mdx_node=>ty_segment
                name          TYPE string
      RETURNING VALUE(result) TYPE abap_bool.
    "! Util.implode: the segments as quoted identifiers, separated by dots.
    CLASS-METHODS implode
      IMPORTING segments      TYPE zzxxmla1_cl_mdx_node=>ty_t_segment
      RETURNING VALUE(result) TYPE string.
    METHODS add_level
      IMPORTING hierarchy     TYPE i
                depth         TYPE i
                name          TYPE string
                is_all        TYPE abap_bool
                key_level     TYPE i DEFAULT 0
      RETURNING VALUE(result) TYPE i.
    "! RolapLevel.lookupChild: a key segment is the member whose keys of the level and of the levels above it, up to a
    "! level of unique members, are the segment's keys (getInheritedKeyExps, getMemberByKey; another number of keys
    "! is an error in the reference, here no member); a name the first member of the level with that name, calculated
    "! members last (getLevelMembers with calculated members, findBestMemberMatch with MatchType.EXACT).
    METHODS lookup_child_of_level
      IMPORTING level         TYPE i
                segment       TYPE zzxxmla1_cl_mdx_node=>ty_segment
      RETURNING VALUE(result) TYPE ty_element.
    "! A member of a level of a BW hierarchy by its key as SSAS names it: InfoObject and name per level from the first
    "! one down to this one, &amp;[0HIER_NODE]&amp;[LOCATIONS]&amp;[ZCLSITE]&amp;[NORTH] (ZZXXMLA1_CL_MODEL, ty_member-unique_name);
    "! another number of keys is no member.
    METHODS lookup_bw_member_by_key
      IMPORTING level         TYPE i
                segment       TYPE zzxxmla1_cl_mdx_node=>ty_segment
      RETURNING VALUE(result) TYPE ty_element.
    METHODS lookup_child_of_cube
      IMPORTING segment       TYPE zzxxmla1_cl_mdx_node=>ty_segment
      RETURNING VALUE(result) TYPE ty_element.
    METHODS lookup_child_of_dimension
      IMPORTING dimension     TYPE i
                segment       TYPE zzxxmla1_cl_mdx_node=>ty_segment
      RETURNING VALUE(result) TYPE ty_element.
    METHODS lookup_child_of_hierarchy
      IMPORTING hierarchy     TYPE i
                segment       TYPE zzxxmla1_cl_mdx_node=>ty_segment
      RETURNING VALUE(result) TYPE ty_element.
    "! Util.lookupHierarchyRootMember: a member of the first level by name, else, below an All member, a child of it.
    METHODS lookup_hierarchy_root_member
      IMPORTING hierarchy     TYPE i
                name          TYPE string
      RETURNING VALUE(result) TYPE ty_element.
    CLASS-METHODS equal_name
      IMPORTING name1         TYPE string
                name2         TYPE string
      RETURNING VALUE(result) TYPE abap_bool.
ENDCLASS.

CLASS zzxxmla1_cl_mdx_schema_reader IMPLEMENTATION.

  METHOD for_cube.
    LOOP AT zzxxmla1_cl_schema=>get( )->cubes( ) INTO DATA(candidate).
      IF ( catalog IS INITIAL OR candidate-catalog_name = catalog ) AND to_upper( candidate-cube_name ) = to_upper( name ).
        result = NEW #( ).
        result->cube = candidate.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF result IS NOT BOUND.
      zzxxmla1_cx_xmla=>raise_code( kind = `Server` code = `00HSBB01` text = `XMLA SOAP Body processing error`
                                    description = |olap4abap Error:MDX cube '{ name }' not found| ).
    ENDIF.
    result->build( ).
  ENDMETHOD.

  METHOD build.
    measures = zzxxmla1_cl_model=>measures( cube-cube_name ).
    model_hierarchies = zzxxmla1_cl_model=>hierarchies( cube-cube_name ).

    " Measures: the first dimension of every cube
    APPEND VALUE #( id = c_measures name = `Measures` unique_name = `[Measures]` is_measures = abap_true
                    hierarchies = VALUE #( ( c_measures ) ) type = `MeasuresDimension` ) TO dimensions.
    APPEND VALUE #( id = c_measures dimension = c_measures name = `Measures` unique_name = `[Measures]` ) TO hierarchies.
    DATA(measures_level) = add_level( hierarchy = c_measures depth = 0 name = `MeasuresLevel` is_all = abap_false ).
    hierarchies[ 1 ]-levels = VALUE #( ( measures_level ) ).

    LOOP AT model_hierarchies INTO DATA(model).
      DATA(hier_id) = sy-tabix.
      DATA(dim_name) = CONV string( model-dim_name ).
      READ TABLE dimensions WITH KEY name = dim_name ASSIGNING FIELD-SYMBOL(<dimension>).
      IF sy-subrc <> 0.
        APPEND VALUE #( id = lines( dimensions ) name = dim_name unique_name = |[{ dim_name }]|
                        type = COND #( WHEN model-dim_type = `Time` THEN `TimeDimension` ELSE `StandardDimension` ) )
               TO dimensions ASSIGNING <dimension>.
      ENDIF.
      APPEND hier_id TO <dimension>-hierarchies.
      APPEND VALUE #( id = hier_id dimension = <dimension>-id name = model-name
                      unique_name = model-unique_name has_all = model-has_all all_member_name = model-all_member_name
                      model = model ) TO hierarchies ASSIGNING FIELD-SYMBOL(<hierarchy>).
      " the (All) level has depth 0, the levels of the model follow it
      DATA(depth) = 0.
      IF model-has_all = abap_true.
        APPEND add_level( hierarchy = hier_id depth = 0 name = `(All)` is_all = abap_true ) TO <hierarchy>-levels.
        depth = 1.
      ENDIF.
      LOOP AT model-levels INTO DATA(model_level).
        APPEND add_level( hierarchy = hier_id depth = depth name = model_level-level_name is_all = abap_false
                          key_level = model_level-level_no ) TO <hierarchy>-levels.
        depth = depth + 1.
      ENDLOOP.
    ENDLOOP.

    " the defaultMember of a hierarchy is looked up once the cube is complete (RolapHierarchy.init)
    LOOP AT model_hierarchies INTO model WHERE default_member IS NOT INITIAL.
      hier_id = sy-tabix.
      INSERT VALUE #( hierarchy = hier_id member = resolve_default_member( hier_id ) ) INTO TABLE default_members.
    ENDLOOP.
  ENDMETHOD.

  METHOD add_level.
    result = lines( levels ) + 1.
    DATA(unique) = COND string( WHEN hierarchy = c_measures THEN `[Measures]`
                                ELSE model_hierarchies[ hierarchy ]-unique_name ).
    APPEND VALUE #( id = result hierarchy = hierarchy depth = depth name = name is_all = is_all key_level = key_level
                    unique_name = |{ unique }.{ zzxxmla1_cl_mdx_node=>quote_identifier( name ) }|
                    type = COND #( WHEN key_level > 0 THEN model_hierarchies[ hierarchy ]-levels[ key_level ]-level_type
                                   ELSE `Regular` ) ) TO levels.
  ENDMETHOD.

  METHOD get_dimensions.
    result = dimensions.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_schema_reader~get_hierarchies.
    result = hierarchies.
  ENDMETHOD.

  METHOD get_model_hierarchies.
    result = model_hierarchies.
  ENDMETHOD.

  METHOD get_dimension.
    result = dimensions[ id + 1 ].
  ENDMETHOD.

  METHOD get_hierarchy.
    result = hierarchies[ id + 1 ].
  ENDMETHOD.

  METHOD get_level.
    result = levels[ id ].
  ENDMETHOD.

  METHOD dimension_of.
    result = hierarchies[ hierarchy + 1 ]-dimension.
  ENDMETHOD.

  METHOD get_dimension_hierarchy.
    result = -1.
    IF dimension < 0.
      RETURN.
    ENDIF.
    DATA(element) = dimensions[ dimension + 1 ].
    IF lines( element-hierarchies ) = 1.
      result = element-hierarchies[ 1 ].
      RETURN.
    ENDIF.
    LOOP AT element-hierarchies INTO DATA(id).
      IF equal_name( name1 = hierarchies[ id + 1 ]-name name2 = element-name ) = abap_true.
        result = id.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_schema_reader~measure_member.
    DATA(level) = levels[ 1 ].
    result = VALUE #( hierarchy = `[Measures]` hier_id = c_measures measure_index = index
                      order_key = |{ zzxxmla1_cl_model=>c_separator }0{ index WIDTH = 10 ALIGN = RIGHT PAD = `0` }|
                      unique_name = |[Measures].{ zzxxmla1_cl_mdx_node=>quote_identifier( measures[ index ]-name ) }|
                      name = measures[ index ]-name caption = measures[ index ]-caption
                      level = level-id level_name = level-unique_name level_number = 0 ).
  ENDMETHOD.

  METHOD read.
    " a query asked before (a range or Lag in a calculation evaluated per cell) is answered from what it read
    DATA(key) = |{ hierarchy }/{ level_no }/{ descending }/{ limit }/{ offset }/{ condition }|.
    READ TABLE queries ASSIGNING FIELD-SYMBOL(<query>) WITH TABLE KEY key = key.
    IF sy-subrc = 0.
      result = <query>-members.
      RETURN.
    ENDIF.
    DATA(model) = model_hierarchies[ hierarchy ].
    IF with_facts = abap_true.
      model-members_with_facts = abap_false.
    ENDIF.
    zzxxmla1_cl_model=>read_members( EXPORTING hierarchy  = model
                                               level_no   = level_no
                                               condition  = condition
                                               descending = descending
                                               limit      = limit
                                               offset     = offset
                                     IMPORTING ancestors  = DATA(ancestors)
                                     RECEIVING result     = DATA(model_members) ).
    " the ancestors are kept too: a parent is then no query of its own
    LOOP AT ancestors INTO DATA(model_member).
      remember( hierarchy = hierarchy model_member = model_member ).
    ENDLOOP.
    LOOP AT model_members INTO model_member.
      APPEND remember( hierarchy = hierarchy model_member = model_member ) TO result.
    ENDLOOP.
    INSERT VALUE #( key = key members = result ) INTO TABLE queries.
  ENDMETHOD.

  METHOD remember.
    ASSIGN cached[ hier_id = hierarchy key_level = model_member-level_no path = model_member-path ]
           TO FIELD-SYMBOL(<cached>).
    IF sy-subrc <> 0.
      DATA(model) = model_hierarchies[ hierarchy ].
      DATA(level) = levels[ level_of( hierarchy = hierarchy level_no = model_member-level_no ) ].
      DATA(all_unique) = COND string( WHEN model-has_all = abap_true THEN all_member( hierarchy )-unique_name ).
      INSERT VALUE #( hier_id = hierarchy key_level = model_member-level_no path = model_member-path
                      properties = model_member-properties
                      member = VALUE #( hierarchy = model-unique_name hier_id = hierarchy
                                        order_key = model_member-order_key key = model_member-key
                                        key_level = model_member-level_no path = model_member-path
                                        unique_name = model_member-unique_name name = model_member-name
                                        caption = model_member-caption
                                        level = level-id level_name = level-unique_name level_number = level-depth
                                        parent_unique = COND #( WHEN model_member-parent IS NOT INITIAL
                                                                THEN model_member-parent ELSE all_unique ) ) )
             INTO TABLE cached ASSIGNING <cached>.
      INSERT VALUE #( hier_id = hierarchy unique_name = model_member-unique_name key_level = model_member-level_no
                      path = model_member-path ) INTO TABLE named.
    ENDIF.
    result = <cached>-member.
  ENDMETHOD.

  METHOD level_of.
    DATA(element) = hierarchies[ hierarchy + 1 ].
    result = element-levels[ level_no + COND i( WHEN element-has_all = abap_true THEN 1 ) ].
  ENDMETHOD.

  METHOD get_level_of.
    result = level_of( hierarchy = hierarchy level_no = key_level ).
  ENDMETHOD.

  METHOD get_level_cardinality.
    DATA(element) = levels[ level ].
    IF element-hierarchy = c_measures.
      result = lines( measures ).
      RETURN.
    ELSEIF element-key_level = 0.
      result = 1.
      RETURN.
    ENDIF.
    READ TABLE level_counts ASSIGNING FIELD-SYMBOL(<count>) WITH TABLE KEY level = level.
    IF sy-subrc <> 0.
      DATA(count) = COND i( WHEN line_exists( level_lists[ level = level ] )
                            THEN lines( level_lists[ level = level ]-members )
                            ELSE zzxxmla1_cl_model=>level_cardinality( hierarchy = model_hierarchies[ element-hierarchy ]
                                                                       level_no  = element-key_level ) ).
      INSERT VALUE #( level = level count = count ) INTO TABLE level_counts ASSIGNING <count>.
    ENDIF.
    result = <count>-count.
  ENDMETHOD.

  METHOD cached_member.
    READ TABLE cached ASSIGNING FIELD-SYMBOL(<cached>)
         WITH TABLE KEY hier_id = hierarchy key_level = key_level path = path.
    IF sy-subrc = 0.
      result = <cached>-member.
    ENDIF.
  ENDMETHOD.

  METHOD member_by_name.
    DATA(element) = levels[ level ].
    IF element-key_level = 0 OR element-hierarchy = c_measures.
      RETURN.
    ENDIF.
    " the children already read: the first with the name
    IF parent IS NOT INITIAL.
      READ TABLE children_lists ASSIGNING FIELD-SYMBOL(<children>)
           WITH TABLE KEY hier_id = parent-hier_id key_level = parent-key_level path = parent-path.
      IF sy-subrc = 0.
        LOOP AT <children>-members INTO DATA(child).
          IF equal_name( name1 = child-name name2 = name ) = abap_true.
            result = child.
            RETURN.
          ENDIF.
        ENDLOOP.
        RETURN.
      ENDIF.
    ENDIF.
    DATA(model) = model_hierarchies[ element-hierarchy ].
    DATA(condition) = zzxxmla1_cl_model=>name_condition( hierarchy = model level_no = element-key_level name = name ).
    IF parent IS NOT INITIAL AND parent-key_level > 0.
      condition = |{ zzxxmla1_cl_model=>path_condition( hierarchy = model level_no = parent-key_level
                                                         path = parent-path ) } AND { condition }|.
    ENDIF.
    DATA(found) = read( hierarchy = element-hierarchy level_no = element-key_level condition = condition limit = 1 ).
    IF found IS NOT INITIAL.
      result = found[ 1 ].
    ENDIF.
  ENDMETHOD.

  METHOD get_all_member.
    IF hierarchy <> c_measures AND model_hierarchies[ hierarchy ]-has_all = abap_true.
      result = all_member( hierarchy ).
    ENDIF.
  ENDMETHOD.

  METHOD get_members_by_paths.
    DATA(element) = levels[ level ].
    IF element-key_level = 0 OR element-hierarchy = c_measures.
      RETURN.
    ENDIF.
    DATA unique TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    DATA(missing) = VALUE string_table( ).
    LOOP AT paths INTO DATA(path).
      INSERT path INTO TABLE unique.
      IF sy-subrc = 0
          AND NOT line_exists( cached[ hier_id = element-hierarchy key_level = element-key_level path = path ] ).
        APPEND path TO missing.
      ENDIF.
    ENDLOOP.
    DATA(model) = model_hierarchies[ element-hierarchy ].
    " more than one query's paths and most of the level: the level in one query
    IF lines( missing ) > zzxxmla1_cl_model=>c_max_constraints
        AND lines( missing ) * 2 > get_level_cardinality( level ).
      get_level_members( level ).
      CLEAR missing.
    ENDIF.
    DATA(chunk) = VALUE string_table( ).
    LOOP AT missing INTO path.
      DATA(last) = xsdbool( sy-tabix = lines( missing ) ).
      APPEND path TO chunk.
      IF lines( chunk ) < zzxxmla1_cl_model=>c_max_constraints AND last = abap_false.
        CONTINUE.
      ENDIF.
      read( hierarchy  = element-hierarchy level_no = element-key_level
            condition  = zzxxmla1_cl_model=>paths_condition( hierarchy = model level_no = element-key_level
                                                             paths = chunk )
            with_facts = abap_true ).
      CLEAR chunk.
    ENDLOOP.
    LOOP AT unique INTO path.
      READ TABLE cached ASSIGNING FIELD-SYMBOL(<cached>)
           WITH TABLE KEY hier_id = element-hierarchy key_level = element-key_level path = path.
      IF sy-subrc = 0.
        APPEND <cached>-member TO result.
      ENDIF.
    ENDLOOP.
    SORT result BY order_key ASCENDING.
  ENDMETHOD.

  METHOD get_lead_member.
    IF n = 0 OR member-is_null = abap_true OR member-hier_id = c_measures OR member-key_level = 0.
      result = COND #( WHEN n = 0 THEN member ).
      RETURN.
    ENDIF.
    DATA(model) = model_hierarchies[ member-hier_id ].
    DATA(found) = read( hierarchy  = member-hier_id
                        level_no   = member-key_level
                        condition  = zzxxmla1_cl_model=>order_condition( hierarchy = model level_no = member-key_level
                                                                         path = member-path
                                                                         operator = COND #( WHEN n > 0 THEN `>`
                                                                                            ELSE `<` ) )
                        descending = xsdbool( n < 0 )
                        limit      = 1
                        offset     = CONV i( abs( n ) - 1 ) ).
    IF found IS NOT INITIAL.
      result = found[ 1 ].
    ENDIF.
  ENDMETHOD.

  METHOD get_member_range.
    IF member1-level <> member2-level OR member1-hier_id = c_measures.
      RETURN.
    ENDIF.
    IF member1-key_level = 0.
      result = VALUE #( ( member1 ) ).
      RETURN.
    ENDIF.
    DATA(first) = COND #( WHEN member1-order_key <= member2-order_key THEN member1 ELSE member2 ).
    DATA(last) = COND #( WHEN member1-order_key <= member2-order_key THEN member2 ELSE member1 ).
    DATA(model) = model_hierarchies[ first-hier_id ].
    result = read( hierarchy = first-hier_id
                   level_no  = first-key_level
                   condition = |{ zzxxmla1_cl_model=>order_condition( hierarchy = model level_no = first-key_level
                                                                      path = first-path operator = `>=` ) } AND | &&
                               zzxxmla1_cl_model=>order_condition( hierarchy = model level_no = last-key_level
                                                                   path = last-path operator = `<=` ) ).
  ENDMETHOD.

  METHOD get_children_count.
    IF member-hier_id = c_measures OR member-calculated = abap_true OR member-is_null = abap_true
        OR member-key_level >= lines( model_hierarchies[ member-hier_id ]-levels ).
      RETURN.
    ENDIF.
    IF NOT line_exists( children_counts[ hier_id = member-hier_id key_level = member-key_level path = member-path ] ).
      prefetch_children_counts( VALUE #( ( member ) ) ).
    ENDIF.
    result = VALUE #( children_counts[ hier_id = member-hier_id key_level = member-key_level
                                       path = member-path ]-count OPTIONAL ).
  ENDMETHOD.

  METHOD prefetch_children_counts.
    TYPES:
      BEGIN OF ty_wanted,
        hier_id   TYPE i,
        key_level TYPE i,
        paths     TYPE string_table,
      END OF ty_wanted.
    DATA wanted TYPE HASHED TABLE OF ty_wanted WITH UNIQUE KEY hier_id key_level.
    DATA seen TYPE HASHED TABLE OF ty_named WITH UNIQUE KEY hier_id key_level path.
    LOOP AT members INTO DATA(member) WHERE hier_id <> c_measures AND calculated = abap_false AND is_null = abap_false.
      IF member-key_level >= lines( model_hierarchies[ member-hier_id ]-levels )
          OR line_exists( children_counts[ hier_id = member-hier_id key_level = member-key_level path = member-path ] ).
        CONTINUE.
      ENDIF.
      " a member counted already from its children read
      READ TABLE children_lists ASSIGNING FIELD-SYMBOL(<children>)
           WITH TABLE KEY hier_id = member-hier_id key_level = member-key_level path = member-path.
      IF sy-subrc = 0.
        INSERT VALUE #( hier_id = member-hier_id key_level = member-key_level path = member-path
                        count = lines( <children>-members ) ) INTO TABLE children_counts.
        CONTINUE.
      ENDIF.
      ASSIGN wanted[ hier_id = member-hier_id key_level = member-key_level ] TO FIELD-SYMBOL(<wanted>).
      IF sy-subrc <> 0.
        INSERT VALUE #( hier_id = member-hier_id key_level = member-key_level ) INTO TABLE wanted ASSIGNING <wanted>.
      ENDIF.
      INSERT VALUE #( hier_id = member-hier_id key_level = member-key_level path = member-path ) INTO TABLE seen.
      IF sy-subrc = 0.
        APPEND member-path TO <wanted>-paths.
      ENDIF.
    ENDLOOP.
    LOOP AT wanted ASSIGNING <wanted>.
      DATA(counts) = zzxxmla1_cl_model=>children_counts( hierarchy = model_hierarchies[ <wanted>-hier_id ]
                                                         level_no = <wanted>-key_level paths = <wanted>-paths ).
      LOOP AT <wanted>-paths INTO DATA(path).
        INSERT VALUE #( hier_id = <wanted>-hier_id key_level = <wanted>-key_level path = path
                        count = VALUE #( counts[ path = path ]-count OPTIONAL ) ) INTO TABLE children_counts.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD all_member.
    DATA(model) = model_hierarchies[ hierarchy ].
    DATA(all_level) = levels[ hierarchies[ hierarchy + 1 ]-levels[ 1 ] ].
    result = VALUE #( hierarchy = model-unique_name hier_id = hierarchy
                      unique_name = |{ model-unique_name }.{ zzxxmla1_cl_model=>quote_name( model-all_member_name ) }|
                      name = model-all_member_name caption = model-all_member_name
                      level = all_level-id level_name = all_level-unique_name
                      level_number = 0 ).
  ENDMETHOD.

  METHOD get_level_properties.
    IF level < 1 OR level > lines( levels ).
      RETURN.
    ENDIF.
    DATA(element) = levels[ level ].
    IF element-key_level > 0.
      result = model_hierarchies[ element-hierarchy ]-levels[ element-key_level ]-properties.
    ENDIF.
  ENDMETHOD.

  METHOD lookup_level_property.
    IF level < 1 OR level > lines( levels ).
      RETURN.
    ENDIF.
    DATA(element) = levels[ level ].
    DATA(key_level) = element-key_level.
    WHILE key_level > 0.
      DATA(properties) = model_hierarchies[ element-hierarchy ]-levels[ key_level ]-properties.
      READ TABLE properties INTO result WITH KEY name = name.
      IF sy-subrc = 0.
        RETURN.
      ENDIF.
      key_level = key_level - 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD is_valid_property.
    IF lookup_level_property( level = level name = name ) IS NOT INITIAL.
      result = abap_true.
      RETURN.
    ENDIF.
    CASE to_upper( name ).
      WHEN `CATALOG_NAME` OR `SCHEMA_NAME` OR `CUBE_NAME` OR `DIMENSION_UNIQUE_NAME` OR `HIERARCHY_UNIQUE_NAME`
        OR `LEVEL_UNIQUE_NAME` OR `LEVEL_NUMBER` OR `MEMBER_ORDINAL` OR `MEMBER_NAME` OR `MEMBER_UNIQUE_NAME`
        OR `MEMBER_TYPE` OR `MEMBER_GUID` OR `MEMBER_CAPTION` OR `CAPTION` OR `CHILDREN_CARDINALITY` OR `PARENT_LEVEL`
        OR `PARENT_UNIQUE_NAME` OR `PARENT_COUNT` OR `DESCRIPTION` OR `CELL_FORMATTER` OR `CELL_FORMATTER_SCRIPT_LANGUAGE`
        OR `CELL_FORMATTER_SCRIPT` OR `VALUE` OR `DEPTH` OR `DISPLAY_INFO` OR `MEMBER_KEY` OR `KEY` OR `DISPLAY_FOLDER`
        OR `FORMAT_EXP` OR `$MEMBER_SCOPE` OR `$SCENARIO`.
        result = abap_true.
    ENDCASE.
  ENDMETHOD.

  METHOD get_property_value.
    CLEAR: property, value, found.
    IF member-calculated = abap_true OR member-is_null = abap_true OR member-hier_id = c_measures
        OR member-key_level = 0.
      RETURN.
    ENDIF.
    LOOP AT get_level_properties( member-level ) INTO property.
      DATA(index) = sy-tabix.
      IF to_upper( property-name ) = to_upper( name ).
        found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF found = abap_false.
      CLEAR property.
      RETURN.
    ENDIF.
    READ TABLE cached ASSIGNING FIELD-SYMBOL(<cached>)
         WITH TABLE KEY hier_id = member-hier_id key_level = member-key_level path = member-path.
    IF sy-subrc = 0.
      value = VALUE #( <cached>-properties[ index ] OPTIONAL ).
    ENDIF.
  ENDMETHOD.

  METHOD get_hierarchy_members.
    IF hierarchy = c_measures.
      DO lines( measures ) TIMES.
        APPEND measure_member( sy-index ) TO result.
      ENDDO.
      RETURN.
    ENDIF.
    LOOP AT hierarchies[ hierarchy + 1 ]-levels INTO DATA(level).
      APPEND LINES OF get_level_members( level ) TO result.
    ENDLOOP.
    SORT result STABLE BY order_key ASCENDING.
  ENDMETHOD.

  METHOD get_level_members.
    DATA(element) = levels[ level ].
    IF element-hierarchy = c_measures.
      result = get_hierarchy_members( element-hierarchy ).
      RETURN.
    ENDIF.
    IF element-is_all = abap_true.
      result = VALUE #( ( all_member( element-hierarchy ) ) ).
      RETURN.
    ENDIF.
    READ TABLE level_lists ASSIGNING FIELD-SYMBOL(<level>) WITH TABLE KEY level = level.
    IF sy-subrc <> 0.
      INSERT VALUE #( level = level members = read( hierarchy = element-hierarchy level_no = element-key_level ) )
             INTO TABLE level_lists ASSIGNING <level>.
    ENDIF.
    result = <level>-members.
  ENDMETHOD.

  METHOD get_level_members_where.
    DATA(element) = levels[ level ].
    IF element-key_level = 0 OR element-hierarchy = c_measures.
      RETURN.
    ENDIF.
    DATA(where) = condition.
    IF ancestor-key_level > 0.
      where = |{ zzxxmla1_cl_model=>path_condition( hierarchy = model_hierarchies[ element-hierarchy ]
                                                     level_no  = ancestor-key_level
                                                     path      = ancestor-path ) } AND ( { where } )|.
    ENDIF.
    result = read( hierarchy = element-hierarchy level_no = element-key_level condition = where ).
  ENDMETHOD.

  METHOD get_hierarchy_root_members.
    result = get_level_members( hierarchies[ hierarchy + 1 ]-levels[ 1 ] ).
  ENDMETHOD.

  METHOD get_member_children.
    " the members whose parent it is, in hierarchy order
    IF member-hier_id = c_measures OR member-calculated = abap_true OR member-is_null = abap_true
        OR member-key_level >= lines( model_hierarchies[ member-hier_id ]-levels ).
      RETURN.
    ENDIF.
    READ TABLE children_lists ASSIGNING FIELD-SYMBOL(<children>)
         WITH TABLE KEY hier_id = member-hier_id key_level = member-key_level path = member-path.
    IF sy-subrc <> 0.
      DATA(children) = COND ty_t_member(
        WHEN member-key_level = 0
        THEN get_level_members( level_of( hierarchy = member-hier_id level_no = 1 ) )
        ELSE read( hierarchy = member-hier_id
                   level_no  = member-key_level + 1
                   condition = zzxxmla1_cl_model=>path_condition( hierarchy = model_hierarchies[ member-hier_id ]
                                                                  level_no  = member-key_level
                                                                  path      = member-path ) ) ).
      INSERT VALUE #( hier_id = member-hier_id key_level = member-key_level path = member-path members = children )
             INTO TABLE children_lists ASSIGNING <children>.
    ENDIF.
    result = <children>-members.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_schema_reader~get_default_member.
    IF hierarchy = c_measures.
      result = measure_member( 1 ).
      RETURN.
    ENDIF.
    " a defaultMember of the schema was resolved by build; else the first root member, the All member needs no read
    " (RolapHierarchy.getDefaultMember)
    ASSIGN default_members[ hierarchy = hierarchy ] TO FIELD-SYMBOL(<default>).
    IF sy-subrc <> 0.
      DATA(first) = get_all_member( hierarchy ).
      IF first IS INITIAL.
        DATA(roots) = read( hierarchy = hierarchy level_no = 1 limit = 1 ).
        first = VALUE #( roots[ 1 ] OPTIONAL ).
      ENDIF.
      INSERT VALUE #( hierarchy = hierarchy member = first ) INTO TABLE default_members ASSIGNING <default>.
    ENDIF.
    result = <default>-member.
  ENDMETHOD.

  METHOD resolve_default_member.
    DATA(name) = model_hierarchies[ hierarchy ]-default_member.
    DATA(id) = zzxxmla1_cl_mdx_parser=>parse_expression( name ).
    DATA(element) = VALUE ty_element( ).
    IF id->kind = zzxxmla1_cl_mdx_node=>c_kind-id.
      element = lookup_compound( segments = id->segments category = zzxxmla1_cl_mdx_type=>c_category-member ).
    ENDIF.
    IF element-kind <> c_element-member OR element-member-hier_id <> hierarchy.
      " Resource.InvalidHierarchyCondition
      zzxxmla1_cx_xmla=>raise_code(
        kind = `Server` code = `00HSBB01` text = `XMLA SOAP Body processing error`
        description = |olap4abap Error:Can not find Default Member with name "{ name }" in Hierarchy | &&
                      |"{ model_hierarchies[ hierarchy ]-hier_name }"| ).
    ENDIF.
    result = element-member.
  ENDMETHOD.

  METHOD equal_name.
    result = xsdbool( to_upper( name1 ) = to_upper( name2 ) ).
  ENDMETHOD.

  METHOD add_calculated_member.
    APPEND VALUE #( member = member ) TO calculated_members.
  ENDMETHOD.

  METHOD get_calculated_member.
    READ TABLE calculated_members INTO result WITH KEY member-unique_name = unique_name.
  ENDMETHOD.

  METHOD set_calculated_member.
    READ TABLE calculated_members TRANSPORTING NO FIELDS WITH KEY member-unique_name = calculated-member-unique_name.
    IF sy-subrc = 0.
      MODIFY calculated_members FROM calculated INDEX sy-tabix.
    ENDIF.
  ENDMETHOD.

  METHOD add_visual_total.
    APPEND calculated TO visual_totals.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_schema_reader~get_measures.
    result = measures.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_schema_reader~get_calculation.
    IF member-calc_name IS INITIAL.
      result = get_calculated_member( member-unique_name ).
    ELSE.
      READ TABLE visual_totals INTO result WITH KEY member-calc_name = member-calc_name.
    ENDIF.
  ENDMETHOD.

  METHOD get_calculated_members.
    LOOP AT calculated_members INTO DATA(calculated) WHERE member-hier_id = hierarchy.
      APPEND calculated-member TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_time_hierarchy.
    result = -1.
    LOOP AT get_hierarchies( ) INTO DATA(hierarchy).
      IF get_dimension( hierarchy-dimension )-type = `TimeDimension`.
        result = hierarchy-id.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_time_level.
    LOOP AT dimensions INTO DATA(dimension) WHERE type = `TimeDimension`.
      LOOP AT dimension-hierarchies INTO DATA(hierarchy).
        DATA(hierarchy_levels) = hierarchies[ hierarchy + 1 ]-levels.
        LOOP AT hierarchy_levels INTO DATA(level).
          IF levels[ level ]-type = level_type.
            result = level.
            RETURN.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_parent_member.
    IF member-parent_unique IS INITIAL OR member-hier_id = c_measures.
      RETURN.
    ENDIF.
    IF member-key_level = 1.
      result = all_member( member-hier_id ).
    ELSEIF member-key_level > 1.
      " a stored member (or a visual total of one): the member with its path without the last key
      DATA(parent_path) = substring_before( val = member-path sub = zzxxmla1_cl_model=>c_separator occ = -1 ).
      result = cached_member( hierarchy = member-hier_id key_level = member-key_level - 1 path = parent_path ).
      IF result IS INITIAL.
        DATA(model) = model_hierarchies[ member-hier_id ].
        DATA(found) = read( hierarchy = member-hier_id level_no = member-key_level - 1 limit = 1
                            condition = zzxxmla1_cl_model=>path_condition( hierarchy = model
                                                                           level_no  = member-key_level - 1
                                                                           path      = parent_path ) ).
        result = VALUE #( found[ 1 ] OPTIONAL ).
      ENDIF.
    ELSE.
      " a calculated member: its parent is a stored member that was looked up when it was defined
      IF get_all_member( member-hier_id )-unique_name = member-parent_unique.
        result = all_member( member-hier_id ).
        RETURN.
      ENDIF.
      READ TABLE named ASSIGNING FIELD-SYMBOL(<named>)
           WITH TABLE KEY hier_id = member-hier_id unique_name = member-parent_unique.
      IF sy-subrc = 0.
        result = cached_member( hierarchy = member-hier_id key_level = <named>-key_level path = <named>-path ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD lookup_calculated_member.
    LOOP AT calculated_members INTO DATA(calculated).
      IF matches( member = calculated-member segments = segments ) = abap_true.
        result = VALUE #( kind = c_element-member id = calculated-member-level member = calculated-member ).
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD matches.
    IF equal_name( name1 = implode( segments ) name2 = member-unique_name ) = abap_true.
      result = abap_true.
      RETURN.
    ENDIF.
    " the names from the end: the member, its ancestors, then the hierarchy
    DATA(names) = segments.
    DATA(current) = member.
    WHILE current-parent_unique IS NOT INITIAL.
      IF names IS INITIAL OR segment_matches( segment = names[ lines( names ) ] name = current-name ) = abap_false.
        RETURN.
      ENDIF.
      current = get_parent_member( current ).
      DELETE names INDEX lines( names ).
    ENDWHILE.
    IF names IS INITIAL.
      RETURN.
    ENDIF.
    IF segment_matches( segment = names[ lines( names ) ] name = current-name ) = abap_true.
      DELETE names INDEX lines( names ).
      result = equal_name( name1 = current-hierarchy name2 = implode( names ) ).
    ELSEIF current-level_number = 0 AND current-hier_id <> c_measures AND current-calculated = abap_false.
      " the All member
      result = equal_name( name1 = current-hierarchy name2 = implode( names ) ).
    ENDIF.
  ENDMETHOD.

  METHOD segment_matches.
    IF segment-quoting <> zzxxmla1_cl_mdx_node=>c_quoting-key.
      result = equal_name( name1 = segment-name name2 = name ).
    ENDIF.
  ENDMETHOD.

  METHOD implode.
    LOOP AT segments INTO DATA(segment).
      DATA(quoted) = segment.
      IF quoted-quoting = zzxxmla1_cl_mdx_node=>c_quoting-unquoted.
        quoted-quoting = zzxxmla1_cl_mdx_node=>c_quoting-quoted.
      ENDIF.
      result = result && COND #( WHEN sy-tabix > 1 THEN `.` ) && zzxxmla1_cl_mdx_node=>unparse_segment( quoted ).
    ENDLOOP.
  ENDMETHOD.

  METHOD get_element_child.
    CASE parent-kind.
      WHEN c_element-cube.
        result = lookup_child_of_cube( segment ).
      WHEN c_element-dimension.
        result = lookup_child_of_dimension( dimension = parent-id segment = segment ).
      WHEN c_element-hierarchy.
        result = lookup_child_of_hierarchy( hierarchy = parent-id segment = segment ).
      WHEN c_element-level.
        result = lookup_child_of_level( level = parent-id segment = segment ).
      WHEN c_element-member.
        IF segment-quoting <> zzxxmla1_cl_mdx_node=>c_quoting-key.
          result = lookup_member_child_by_name( member = parent-member name = segment-name ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD lookup_child_of_level.
    DATA(element) = levels[ level ].
    IF segment-quoting = zzxxmla1_cl_mdx_node=>c_quoting-key.
      IF element-key_level = 0.
        RETURN.
      ENDIF.
      IF hierarchies[ element-hierarchy + 1 ]-model-bw_hierarchy IS NOT INITIAL.
        result = lookup_bw_member_by_key( level = level segment = segment ).
        RETURN.
      ENDIF.
      " the keys from this level up to a level of unique members (the first level below the All level ends it too)
      DATA(model_levels) = hierarchies[ element-hierarchy + 1 ]-model-levels.
      DATA(number) = element-key_level.
      DATA(count) = 1.
      WHILE number > 1 AND model_levels[ number ]-unique_members = abap_false.
        number = number - 1.
        count = count + 1.
      ENDWHILE.
      IF lines( segment-keys ) <> count.
        RETURN.
      ENDIF.
      " the first key is the one of this level, the next ones of the levels above it
      DATA(model) = model_hierarchies[ element-hierarchy ].
      DATA(conditions) = VALUE string_table( ).
      LOOP AT segment-keys INTO DATA(key).
        DATA(key_column) = model-levels[ element-key_level - sy-tabix + 1 ]-key_column.
        APPEND zzxxmla1_cl_sql=>key_condition( column = zzxxmla1_cl_sql=>quote( key_column ) key = key-name )
               TO conditions.
      ENDLOOP.
      DATA(found) = read( hierarchy = element-hierarchy level_no = element-key_level limit = 1
                          condition = concat_lines_of( table = conditions sep = ` AND ` ) ).
      IF found IS NOT INITIAL.
        result = VALUE #( kind = c_element-member id = found[ 1 ]-level member = found[ 1 ] ).
      ENDIF.
      RETURN.
    ENDIF.

    DATA(named_member) = member_by_name( level = level name = segment-name ).
    IF named_member IS NOT INITIAL.
      result = VALUE #( kind = c_element-member id = named_member-level member = named_member ).
      RETURN.
    ENDIF.
    LOOP AT get_calculated_members( element-hierarchy ) INTO DATA(named) WHERE level = level.
      IF equal_name( name1 = named-name name2 = segment-name ) = abap_true.
        result = VALUE #( kind = c_element-member id = named-level member = named ).
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD lookup_bw_member_by_key.
    " the key of the path: InfoObject and name per level from the first one (ZZXXMLA1_CL_MODEL, ty_member-unique_name)
    DATA(element) = levels[ level ].
    IF lines( segment-keys ) <> 2 * element-key_level.
      RETURN.
    ENDIF.
    DATA(model) = model_hierarchies[ element-hierarchy ].
    DATA(conditions) = VALUE string_table( ).
    DO element-key_level TIMES.
      DATA(level_no) = sy-index.
      APPEND zzxxmla1_cl_sql=>key_condition(
               column = zzxxmla1_cl_sql=>quote( zzxxmla1_cl_model=>bw_iobj_column( level_no ) )
               key    = segment-keys[ 2 * level_no - 1 ]-name ) TO conditions.
      APPEND zzxxmla1_cl_sql=>key_condition( column = zzxxmla1_cl_sql=>quote( model-levels[ level_no ]-name_column )
                                             key    = segment-keys[ 2 * level_no ]-name ) TO conditions.
    ENDDO.
    DATA(found) = read( hierarchy = element-hierarchy level_no = element-key_level limit = 1
                        condition = concat_lines_of( table = conditions sep = ` AND ` ) ).
    IF found IS NOT INITIAL.
      result = VALUE #( kind = c_element-member id = found[ 1 ]-level member = found[ 1 ] ).
    ENDIF.
  ENDMETHOD.

  METHOD lookup_child_of_cube.
    " RolapCube.lookupChild: only name segments
    IF segment-quoting = zzxxmla1_cl_mdx_node=>c_quoting-key.
      RETURN.
    ENDIF.
    " CubeBase.lookupChild: a dimension, a hierarchy named [dimension.hierarchy], then the hierarchies, levels and
    " members of the dimensions
    LOOP AT dimensions INTO DATA(dimension).
      IF equal_name( name1 = dimension-name name2 = segment-name ) = abap_true.
        result = VALUE #( kind = c_element-dimension id = dimension-id ).
        RETURN.
      ENDIF.
    ENDLOOP.
    LOOP AT hierarchies INTO DATA(hierarchy) WHERE name = segment-name.
      result = VALUE #( kind = c_element-hierarchy id = hierarchy-id ).
      RETURN.
    ENDLOOP.
    LOOP AT dimensions INTO dimension.
      result = lookup_child_of_dimension( dimension = dimension-id segment = segment ).
      IF result-kind IS NOT INITIAL.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD lookup_child_of_dimension.
    " DimensionBase.lookupChild (SsasCompatibleNaming=false): a hierarchy of the dimension, but a level (or member) of
    " the default hierarchy overrides a hierarchy that has the dimension's name
    DATA(dim) = dimensions[ dimension + 1 ].
    IF segment-quoting <> zzxxmla1_cl_mdx_node=>c_quoting-key.
      LOOP AT dim-hierarchies INTO DATA(hier_id).
        IF equal_name( name1 = hierarchies[ hier_id + 1 ]-name name2 = segment-name ) = abap_true.
          result = VALUE #( kind = c_element-hierarchy id = hier_id ).
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDIF.
    IF result-kind IS INITIAL
        OR equal_name( name1 = hierarchies[ result-id + 1 ]-name name2 = dim-name ) = abap_true.
      DATA(level) = lookup_child_of_hierarchy( hierarchy = dim-hierarchies[ 1 ] segment = segment ).
      IF level-kind IS NOT INITIAL.
        result = level.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD lookup_child_of_hierarchy.
    " HierarchyBase.lookupChild: a level, else a root member; a key segment searches the bottom level, whose
    " lookupChild takes names only. A BW hierarchy's member by its key without the level, as SSAS finds it: the level
    " is the key's number of pairs
    IF segment-quoting = zzxxmla1_cl_mdx_node=>c_quoting-key.
      IF hierarchies[ hierarchy + 1 ]-model-bw_hierarchy IS NOT INITIAL AND lines( segment-keys ) MOD 2 = 0.
        DATA(levels_of) = hierarchies[ hierarchy + 1 ]-levels.
        DATA(position) = lines( segment-keys ) / 2 + COND i( WHEN hierarchies[ hierarchy + 1 ]-has_all = abap_true
                                                            THEN 1 ).
        IF position BETWEEN 1 AND lines( levels_of ).
          result = lookup_bw_member_by_key( level = levels_of[ position ] segment = segment ).
        ENDIF.
      ENDIF.
      RETURN.
    ENDIF.
    LOOP AT hierarchies[ hierarchy + 1 ]-levels INTO DATA(level_id).
      IF equal_name( name1 = levels[ level_id ]-name name2 = segment-name ) = abap_true.
        result = VALUE #( kind = c_element-level id = level_id ).
        RETURN.
      ENDIF.
    ENDLOOP.
    result = lookup_hierarchy_root_member( hierarchy = hierarchy name = segment-name ).
  ENDMETHOD.

  METHOD lookup_hierarchy_root_member.
    IF hierarchy = c_measures.
      LOOP AT get_hierarchy_members( hierarchy ) INTO DATA(measure).
        IF equal_name( name1 = measure-name name2 = name ) = abap_true.
          result = VALUE #( kind = c_element-member id = measure-level member = measure ).
          RETURN.
        ENDIF.
      ENDLOOP.
      RETURN.
    ENDIF.
    DATA(all) = get_all_member( hierarchy ).
    IF all IS INITIAL.
      DATA(root) = member_by_name( level = hierarchies[ hierarchy + 1 ]-levels[ 1 ] name = name ).
      IF root IS NOT INITIAL.
        result = VALUE #( kind = c_element-member id = root-level member = root ).
      ENDIF.
      RETURN.
    ENDIF.
    IF equal_name( name1 = all-name name2 = name ) = abap_true.
      result = VALUE #( kind = c_element-member id = all-level member = all ).
      RETURN.
    ENDIF.
    " the first level is the All level: '[USA]' stands for '[All Customers].[USA]'
    result = lookup_member_child_by_name( member = all name = name ).
  ENDMETHOD.

  METHOD lookup_member_child_by_name.
    IF member-hier_id = c_measures OR member-calculated = abap_true OR member-is_null = abap_true
        OR member-key_level >= lines( model_hierarchies[ member-hier_id ]-levels ).
      RETURN.
    ENDIF.
    DATA(child) = member_by_name( level = level_of( hierarchy = member-hier_id level_no = member-key_level + 1 )
                                  name = name parent = member ).
    IF child IS NOT INITIAL.
      result = VALUE #( kind = c_element-member id = child-level member = child ).
    ENDIF.
  ENDMETHOD.

  METHOD lookup_compound.
    " a calculated member of the query first (Util.lookupCompound: getCalculatedMember before the walk, which reads
    " members by name)
    IF category = zzxxmla1_cl_mdx_type=>c_category-unknown OR category = zzxxmla1_cl_mdx_type=>c_category-member.
      result = lookup_calculated_member( segments ).
      IF result-kind IS NOT INITIAL.
        RETURN.
      ENDIF.
    ENDIF.
    DATA(parent) = VALUE ty_element( kind = c_element-cube ).
    LOOP AT segments INTO DATA(segment).
      DATA(child) = get_element_child( parent = parent segment = segment ).
      IF child-kind IS INITIAL.
        RETURN.
      ENDIF.
      parent = child.
    ENDLOOP.

    CASE category.
      WHEN zzxxmla1_cl_mdx_type=>c_category-dimension.
        IF parent-kind = c_element-dimension.
          result = parent.
        ELSEIF parent-kind = c_element-hierarchy.
          result = VALUE #( kind = c_element-dimension id = dimension_of( parent-id ) ).
        ENDIF.
      WHEN zzxxmla1_cl_mdx_type=>c_category-hierarchy.
        IF parent-kind = c_element-hierarchy.
          result = parent.
        ELSEIF parent-kind = c_element-dimension.
          result = VALUE #( kind = c_element-hierarchy id = dimensions[ parent-id + 1 ]-hierarchies[ 1 ] ).
        ENDIF.
      WHEN zzxxmla1_cl_mdx_type=>c_category-level.
        IF parent-kind = c_element-level.
          result = parent.
        ENDIF.
      WHEN zzxxmla1_cl_mdx_type=>c_category-member.
        IF parent-kind = c_element-member.
          result = parent.
        ENDIF.
      WHEN OTHERS.
        result = parent.
    ENDCASE.
  ENDMETHOD.

ENDCLASS.
