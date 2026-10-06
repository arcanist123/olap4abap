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
    TYPES ty_t_id TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_member,
        hierarchy     TYPE string,   " unique name of the hierarchy
        hier_id       TYPE i,        " id of the hierarchy: 0 for Measures, else the position in the model
        measure_index TYPE i,        " position in the measures (Measures hierarchy only)
        ordinal       TYPE i,        " position in the hierarchy in hierarchy order, the All member first (0)
        key           TYPE string,   " value of the level column; empty for the All member
        key_level     TYPE i,        " the level in the model (1 the first below the All level), 0: the All member
        path          TYPE string,   " the keys of the model levels down to key_level (ZZXXMLA1_CL_MODEL)
        unique_name   TYPE string,
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
      "! (getCompiledExpression) instead of an expression, and is not calculated in the query (cube scope).
      BEGIN OF ty_calculated_member,
        member             TYPE ty_member,
        expression         TYPE REF TO zzxxmla1_cl_mdx_node,
        format_expression  TYPE REF TO zzxxmla1_cl_mdx_node,
        contains_aggregate TYPE abap_bool,
        calc               TYPE REF TO zzxxmla1_if_mdx_calc,
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
    METHODS get_hierarchies RETURNING VALUE(result) TYPE ty_t_hierarchy.
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
    "! The members of a hierarchy in hierarchy order (the All member first); read once.
    METHODS get_hierarchy_members
      IMPORTING hierarchy     TYPE i
      RETURNING VALUE(result) TYPE ty_t_member.
    METHODS get_level_members
      IMPORTING level         TYPE i
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The members of the first level of a hierarchy.
    METHODS get_hierarchy_root_members
      IMPORTING hierarchy     TYPE i
      RETURNING VALUE(result) TYPE ty_t_member.
    METHODS get_member_children
      IMPORTING member        TYPE ty_member
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The default member (RolapHierarchy.init): the hierarchy's defaultMember, else the first root member (the All
    "! member, without one the first member of the first level), for Measures the first measure.
    METHODS get_default_member
      IMPORTING hierarchy     TYPE i
      RETURNING VALUE(result) TYPE ty_member.
    "! The member with the unique name in the hierarchy; initial if there is none.
    METHODS get_member
      IMPORTING hierarchy     TYPE i
                unique_name   TYPE string
      RETURNING VALUE(result) TYPE ty_member.
    "! The member of a measure (1 is the first).
    METHODS measure_member
      IMPORTING index         TYPE i
      RETURNING VALUE(result) TYPE ty_member.
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
    "! The calculation of a calculated member: a visual total by its calc_name, else by its unique name.
    METHODS get_calculation
      IMPORTING member        TYPE ty_member
      RETURNING VALUE(result) TYPE ty_calculated_member.
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
    TYPES ty_t_member_store TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY
      WITH NON-UNIQUE SORTED KEY by_parent COMPONENTS parent_unique
      WITH NON-UNIQUE SORTED KEY by_unique COMPONENTS unique_name.
    TYPES:
      "! the values of the member properties of a member, in the order of its level's properties
      BEGIN OF ty_member_properties,
        unique_name TYPE string,
        values      TYPE string_table,
      END OF ty_member_properties,
      ty_t_member_properties TYPE HASHED TABLE OF ty_member_properties WITH UNIQUE KEY unique_name.
    TYPES:
      BEGIN OF ty_cache,
        hierarchy      TYPE i,
        members        TYPE ty_t_member_store,
        default_member TYPE ty_member,
        properties     TYPE ty_t_member_properties,  " of the members whose level has properties
      END OF ty_cache.
    DATA dimensions        TYPE ty_t_dimension.
    DATA hierarchies       TYPE ty_t_hierarchy.
    DATA levels            TYPE ty_t_level.
    DATA model_hierarchies TYPE zzxxmla1_cl_model=>ty_t_hierarchy.
    DATA cache             TYPE HASHED TABLE OF ty_cache WITH UNIQUE KEY hierarchy.
    DATA calculated_members TYPE ty_t_calculated_member.
    DATA visual_totals TYPE ty_t_calculated_member.

    METHODS build
      RAISING zzxxmla1_cx_xmla.
    "! Reads the members of a hierarchy once (the All member, then the members of the model in hierarchy order).
    METHODS load_members
      IMPORTING hierarchy TYPE i.
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
      DATA(default_member) = resolve_default_member( hier_id ).
      load_members( hier_id ).
      ASSIGN cache[ hierarchy = hier_id ] TO FIELD-SYMBOL(<cache>).
      <cache>-default_member = default_member.
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

  METHOD get_hierarchies.
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

  METHOD measure_member.
    DATA(level) = levels[ 1 ].
    result = VALUE #( hierarchy = `[Measures]` hier_id = c_measures measure_index = index ordinal = index
                      unique_name = |[Measures].{ zzxxmla1_cl_mdx_node=>quote_identifier( measures[ index ]-name ) }|
                      caption = measures[ index ]-name level = level-id level_name = level-unique_name level_number = 0 ).
  ENDMETHOD.

  METHOD load_members.
    IF line_exists( cache[ hierarchy = hierarchy ] ).
      RETURN.
    ENDIF.
    DATA(model) = model_hierarchies[ hierarchy ].
    DATA(element) = hierarchies[ hierarchy + 1 ].
    DATA(model_members) = zzxxmla1_cl_model=>members( model ).
    DATA(members) = VALUE ty_t_member_store( ).
    DATA(properties) = VALUE ty_t_member_properties( ).
    " the (All) level comes first if the hierarchy has one; the levels of the model follow it
    DATA(offset) = 0.
    DATA(all_unique) = VALUE string( ).
    IF model-has_all = abap_true.
      offset = 1.
      DATA(all_level) = levels[ element-levels[ 1 ] ].
      all_unique = |{ model-unique_name }.{ zzxxmla1_cl_model=>quote_name( model-all_member_name ) }|.
      APPEND VALUE #( hierarchy = model-unique_name hier_id = hierarchy ordinal = 0 unique_name = all_unique
                      caption = model-all_member_name level = all_level-id level_name = all_level-unique_name
                      level_number = 0
                      children = REDUCE i( INIT n = 0 FOR m IN model_members WHERE ( level_no = 1 ) NEXT n = n + 1 ) )
             TO members.
    ENDIF.
    LOOP AT model_members INTO DATA(model_member).
      DATA(level) = levels[ element-levels[ model_member-level_no + offset ] ].
      APPEND VALUE #( hierarchy = model-unique_name hier_id = hierarchy ordinal = sy-tabix key = model_member-key
                      key_level = model_member-level_no path = model_member-path
                      unique_name = model_member-unique_name caption = model_member-name level = level-id
                      level_name = level-unique_name level_number = level-depth
                      parent_unique = COND #( WHEN model_member-parent IS NOT INITIAL THEN model_member-parent
                                              ELSE all_unique )
                      children = model_member-children ) TO members.
      IF model_member-properties IS NOT INITIAL.
        INSERT VALUE #( unique_name = model_member-unique_name values = model_member-properties ) INTO TABLE properties.
      ENDIF.
    ENDLOOP.
    INSERT VALUE #( hierarchy = hierarchy members = members properties = properties ) INTO TABLE cache.
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
    load_members( member-hier_id ).
    ASSIGN cache[ hierarchy = member-hier_id ] TO FIELD-SYMBOL(<cache>).
    READ TABLE <cache>-properties INTO DATA(entry) WITH TABLE KEY unique_name = member-unique_name.
    IF sy-subrc = 0.
      value = entry-values[ index ].
    ENDIF.
  ENDMETHOD.

  METHOD get_hierarchy_members.
    IF hierarchy = c_measures.
      DO lines( measures ) TIMES.
        APPEND measure_member( sy-index ) TO result.
      ENDDO.
      RETURN.
    ENDIF.
    load_members( hierarchy ).
    ASSIGN cache[ hierarchy = hierarchy ] TO FIELD-SYMBOL(<cache>).
    result = <cache>-members.
  ENDMETHOD.

  METHOD get_level_members.
    DATA(hierarchy) = levels[ level ]-hierarchy.
    IF hierarchy = c_measures.
      result = get_hierarchy_members( hierarchy ).
      RETURN.
    ENDIF.
    load_members( hierarchy ).
    ASSIGN cache[ hierarchy = hierarchy ] TO FIELD-SYMBOL(<cache>).
    LOOP AT <cache>-members INTO DATA(member) WHERE level = level.
      APPEND member TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_member.
    IF hierarchy = c_measures.
      DATA(measure_members) = get_hierarchy_members( hierarchy ).
      READ TABLE measure_members INTO result WITH KEY unique_name = unique_name.
      RETURN.
    ENDIF.
    load_members( hierarchy ).
    ASSIGN cache[ hierarchy = hierarchy ] TO FIELD-SYMBOL(<cache>).
    READ TABLE <cache>-members INTO result WITH KEY by_unique COMPONENTS unique_name = unique_name.
  ENDMETHOD.

  METHOD get_hierarchy_root_members.
    result = get_level_members( hierarchies[ hierarchy + 1 ]-levels[ 1 ] ).
  ENDMETHOD.

  METHOD get_member_children.
    " the members whose parent it is, in hierarchy order
    IF member-hier_id = c_measures OR member-calculated = abap_true.
      RETURN.
    ENDIF.
    load_members( member-hier_id ).
    ASSIGN cache[ hierarchy = member-hier_id ] TO FIELD-SYMBOL(<cache>).
    LOOP AT <cache>-members INTO DATA(child) USING KEY by_parent WHERE parent_unique = member-unique_name.
      APPEND child TO result.
    ENDLOOP.
    SORT result BY ordinal ASCENDING.
  ENDMETHOD.

  METHOD get_default_member.
    IF hierarchy = c_measures.
      result = measure_member( 1 ).
      RETURN.
    ENDIF.
    " a defaultMember of the schema was resolved by build
    load_members( hierarchy ).
    ASSIGN cache[ hierarchy = hierarchy ] TO FIELD-SYMBOL(<cache>).
    IF <cache>-default_member IS INITIAL.
      DATA(roots) = get_hierarchy_root_members( hierarchy ).
      <cache>-default_member = roots[ 1 ].
    ENDIF.
    result = <cache>-default_member.
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

  METHOD get_calculation.
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
    IF member-parent_unique IS INITIAL.
      RETURN.
    ENDIF.
    result = get_member( hierarchy = member-hier_id unique_name = member-parent_unique ).
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
      IF names IS INITIAL OR segment_matches( segment = names[ lines( names ) ] name = current-caption ) = abap_false.
        RETURN.
      ENDIF.
      current = get_parent_member( current ).
      DELETE names INDEX lines( names ).
    ENDWHILE.
    IF names IS INITIAL.
      RETURN.
    ENDIF.
    IF segment_matches( segment = names[ lines( names ) ] name = current-caption ) = abap_true.
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
      LOOP AT get_level_members( level ) INTO DATA(member).
        SPLIT member-path AT zzxxmla1_cl_model=>c_separator INTO TABLE DATA(path).
        DATA(matches) = abap_true.
        LOOP AT segment-keys INTO DATA(key).
          IF path[ element-key_level - sy-tabix + 1 ] <> key-name.
            matches = abap_false.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF matches = abap_true.
          result = VALUE #( kind = c_element-member id = member-level member = member ).
          RETURN.
        ENDIF.
      ENDLOOP.
      RETURN.
    ENDIF.

    LOOP AT get_level_members( level ) INTO DATA(named).
      IF equal_name( name1 = named-caption name2 = segment-name ) = abap_true.
        result = VALUE #( kind = c_element-member id = named-level member = named ).
        RETURN.
      ENDIF.
    ENDLOOP.
    LOOP AT get_calculated_members( element-hierarchy ) INTO named WHERE level = level.
      IF equal_name( name1 = named-caption name2 = segment-name ) = abap_true.
        result = VALUE #( kind = c_element-member id = named-level member = named ).
        RETURN.
      ENDIF.
    ENDLOOP.
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
    " lookupChild takes names only
    IF segment-quoting = zzxxmla1_cl_mdx_node=>c_quoting-key.
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
    DATA(roots) = get_hierarchy_root_members( hierarchy ).
    LOOP AT roots INTO DATA(root).
      IF equal_name( name1 = root-caption name2 = name ) = abap_true.
        result = VALUE #( kind = c_element-member id = root-level member = root ).
        RETURN.
      ENDIF.
    ENDLOOP.
    " if the first level is the All level, '[USA]' stands for '[All Customers].[USA]'
    IF roots IS NOT INITIAL AND roots[ 1 ]-level_number = 0 AND roots[ 1 ]-hier_id <> c_measures.
      result = lookup_member_child_by_name( member = roots[ 1 ] name = name ).
    ENDIF.
  ENDMETHOD.

  METHOD lookup_member_child_by_name.
    LOOP AT get_member_children( member ) INTO DATA(child).
      IF equal_name( name1 = child-caption name2 = name ) = abap_true.
        result = VALUE #( kind = c_element-member id = child-level member = child ).
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD lookup_compound.
    DATA(parent) = VALUE ty_element( kind = c_element-cube ).
    LOOP AT segments INTO DATA(segment).
      DATA(child) = get_element_child( parent = parent segment = segment ).
      IF child-kind IS INITIAL.
        CLEAR parent.
        EXIT.
      ENDIF.
      parent = child.
    ENDLOOP.
    " not an element of the cube: a calculated member of the query (QuerySchemaReader.lookupCompoundInternal)
    IF parent-kind IS INITIAL.
      IF category = zzxxmla1_cl_mdx_type=>c_category-unknown OR category = zzxxmla1_cl_mdx_type=>c_category-member.
        result = lookup_calculated_member( segments ).
      ENDIF.
      RETURN.
    ENDIF.

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
