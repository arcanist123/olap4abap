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
"! The schemas of the server's catalogs (ZZXXMLA1_CL_REPOSITORY: the catalogs of datasources.xml, each the schema file
"! its Definition names among the server's files), read as the reference reads them (ZZXXMLA1_CL_SCHEMA_DEF)
"! and turned into the cubes, dimensions, hierarchies, levels and measures that the engine and the rowsets work with:
"! the part of RolapSchema the engine needs so far. A dimension is the reference server's attribute model
"! (RolapDimension): first its Hierarchy elements, each with levels over the dimension's table (a level's column is
"! the key column of its sourceAttribute, or its own column), then each DimensionAttribute (unless
"! attributeHierarchyEnabled is false) as a hierarchy with an All member and one level on the attribute's key column,
"! named like the attribute. A hierarchy named like the dimension (an unnamed Hierarchy, an attribute named like the
"! dimension) is the dimension's [Dimension], the others are [Dimension.Hierarchy]. What the reference can express but the
"! engine cannot yet (parent-child levels, property formatters, virtual cubes, dimensions without a table, ...) is
"! refused when the schema is read. A level's member properties (Property) are columns of the dimension's table: the
"! key column of their sourceAttribute, or their own column. A TimeDimension needs time level types on all its levels, a standard dimension none
"! (RolapLevel, RolapDimension); without a type the first level decides.
"! A Hierarchy annotated c_bw_hierarchy (our extension) is a BW hierarchy of the dimension's characteristic, served
"! from its copy (ZZXXMLA1_CL_BW_HIERARCHY_COPY) at BW's current version: it has no levels in the schema, they are
"! Level 01 to Level nn, nn the copy's depth, a member on the level of its depth as SSAS serves a parent-child
"! hierarchy (docs/next-steps.md, Reference scenario, decided 2026-10-16).
CLASS zzxxmla1_cl_schema DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    TYPES:
      "! a catalog: its name and its schema
      BEGIN OF ty_catalog,
        name       TYPE string,
        schema     TYPE string,      " the schema as XML
        updated_at TYPE timestampl,  " when the schema was last changed (MDSCHEMA_CUBES LAST_SCHEMA_UPDATE), UTC
      END OF ty_catalog,
      ty_t_catalog TYPE STANDARD TABLE OF ty_catalog WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_cube,
        cube_name    TYPE string,
        catalog_name TYPE string,
        caption      TYPE string,
        fact_table   TYPE string,
        generated_at TYPE timestampl,  " when the schema was last changed
        "! the empty cells of an answer are not written (the annotation c_omit_empty_cells)
        omit_empty_cells TYPE abap_bool,
      END OF ty_cube,
      ty_t_cube TYPE STANDARD TABLE OF ty_cube WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_dim,
        cube_name  TYPE string,
        dim_name   TYPE string,
        seq_no     TYPE i,        " position in the cube, from 1
        caption    TYPE string,
        fk_column  TYPE string,   " column of the fact table
        dim_table  TYPE string,   " table (or view) of the dimension
        key_column TYPE string,   " column of the dimension table the foreign key refers to
        dim_type   TYPE string,   " Standard or Time
        "! only the members with facts in the cube (the annotation c_members_with_facts)
        members_with_facts TYPE abap_bool,
      END OF ty_dim,
      ty_t_dim TYPE STANDARD TABLE OF ty_dim WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_hier,
        cube_name       TYPE string,
        dim_name        TYPE string,
        hier_name       TYPE string,
        name            TYPE string,  " The reference's name: Dimension.Hierarchy, the dimension's for an unnamed Hierarchy
        seq_no          TYPE i,   " position in the dimension, from 1
        caption         TYPE string,
        has_all         TYPE abap_bool,
        all_member_name TYPE string,
        default_member  TYPE string,  " unique name of the default member; empty: the All member or the first member
        origin          TYPE i,       " HIERARCHY_ORIGIN: 1 user-defined, 2 attribute, 6 key attribute
        "! the copy of the BW hierarchy the annotation c_bw_hierarchy names, current when the schema was read; initial
        "! for any other hierarchy
        bw_hierarchy    TYPE zzxxmla1_cl_bw_hierarchy_copy=>ty_hierarchy,
      END OF ty_hier,
      ty_t_hier TYPE STANDARD TABLE OF ty_hier WITH EMPTY KEY.
    TYPES:
      "! A member property of a level (RolapProperty): a column of the dimension table and the reference's property type
      BEGIN OF ty_property,
        name      TYPE string,
        caption   TYPE string,
        column    TYPE string,
        data_type TYPE string,   " String, Numeric, Integer, Long or Boolean
      END OF ty_property,
      ty_t_property TYPE STANDARD TABLE OF ty_property WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_level,
        cube_name      TYPE string,
        dim_name       TYPE string,
        hier_name      TYPE string,
        level_no       TYPE i,    " position in the hierarchy without the (All) level, from 1
        level_name     TYPE string,
        caption        TYPE string,
        key_column     TYPE string,
        name_column    TYPE string,   " the member names; the key column if the level has no name column
        "! the members' order (a level's ordinalColumn, an attribute's OrderByColumn); initial: the key's
        ordinal_column TYPE string,
        data_type      TYPE string,   " Numeric or String
        unique_members TYPE abap_bool,
        level_type     TYPE string,   " LevelType: Regular, TimeYears, TimeQuarters, TimeMonths, ...
        properties     TYPE ty_t_property,  " the level's own member properties, in the order of the schema
      END OF ty_level,
      ty_t_level TYPE STANDARD TABLE OF ty_level WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_measure,
        cube_name     TYPE string,
        meas_name     TYPE string,
        seq_no        TYPE i,     " position in the cube, from 1; the first is the default measure
        caption       TYPE string,
        fact_column   TYPE string,
        aggregator    TYPE string,
        format_string TYPE string,
        visible       TYPE abap_bool,
      END OF ty_measure,
      ty_t_measure TYPE STANDARD TABLE OF ty_measure WITH EMPTY KEY.
    TYPES:
      "! A column of a cube's drill-through action (RolapDrillThroughColumn): its name and what it reads, a level (the
      "! first level of the hierarchy, of the dimension's first hierarchy, if none is named), a column of the dimension's
      "! table (a DrillThroughAttribute with a sourceAttribute: the attribute's key column) or a measure.
      BEGIN OF ty_drill_column,
        cube_name  TYPE string,
        name       TYPE string,
        dim_name   TYPE string,
        hier_name  TYPE string,   " empty: the dimension's first hierarchy
        level_name TYPE string,   " empty: the first level of the hierarchy
        column     TYPE string,   " a column of the dimension's table; then no hierarchy and level
        meas_name  TYPE string,   " a measure; then no dimension
      END OF ty_drill_column,
      ty_t_drill_column TYPE STANDARD TABLE OF ty_drill_column WITH EMPTY KEY.

    "! The annotation of a Dimension or DimensionUsage (our extension, which the reference ignores) whose value true
    "! makes the cube show only the members of the dimension that have facts in it (ZZXXMLA1_CL_MODEL=>member_table): a
    "! BW characteristic is shared by many providers, which use few of its values. On a DimensionUsage it overrides the
    "! shared Dimension's. Not on a time dimension yet (docs/mvp-scope.md, Members with facts).
    CONSTANTS c_members_with_facts TYPE string VALUE `olap4abap.membersWithFacts`.
    "! The annotation of a Cube (our extension, which the reference ignores) whose value true leaves the empty cells
    "! out of the cells of an Execute answer, but the first, as the reference leaves out a cell without any property
    "! (MDDataSet_Multidimensional.emitCell): the reference writes every empty cell with its format string, so a grid
    "! of few cells with facts is mostly empty cells. Default false, the reference's answer.
    CONSTANTS c_omit_empty_cells TYPE string VALUE `olap4abap.omitEmptyCells`.
    "! The annotation of a Hierarchy (our extension, which the reference ignores) whose value names a BW hierarchy
    "! (RSHIEDIR-HIENM) of the characteristic of the dimension's table (ZZXXMLA1_CL_BW_VIEW_GEN=>characteristic_of_view):
    "! the hierarchy has no Level elements, its levels are made from the copy's depth.
    CONSTANTS c_bw_hierarchy TYPE string VALUE `olap4abap.bwHierarchy`.
    "! The names of a BW hierarchy's levels: Level 01, Level 02, ...
    CONSTANTS c_bw_level_prefix TYPE string VALUE `Level `.

    "! The schemas of all catalogs of the server, read once per session.
    CLASS-METHODS get
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_schema
      RAISING   zzxxmla1_cx_xmla.
    "! The schemas of the given catalogs.
    CLASS-METHODS of_catalogs
      IMPORTING catalogs      TYPE ty_t_catalog
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_schema
      RAISING   zzxxmla1_cx_xmla.

    "! The names of the catalogs, sorted.
    METHODS catalogs
      RETURNING VALUE(result) TYPE string_table.
    "! The cubes, sorted by catalog and name.
    METHODS cubes
      RETURNING VALUE(result) TYPE ty_t_cube.
    "! The dimensions of a cube in the order of the cube.
    METHODS dimensions
      IMPORTING cube          TYPE csequence
      RETURNING VALUE(result) TYPE ty_t_dim.
    "! The hierarchies of a dimension in the order of the dimension.
    METHODS hierarchies
      IMPORTING cube          TYPE csequence
                dim           TYPE csequence
      RETURNING VALUE(result) TYPE ty_t_hier.
    "! The levels of a hierarchy (without the (All) level) from the top.
    METHODS levels
      IMPORTING cube          TYPE csequence
                dim           TYPE csequence
                hier          TYPE csequence
      RETURNING VALUE(result) TYPE ty_t_level.
    "! The measures of a cube in the order of the cube.
    METHODS measures
      IMPORTING cube          TYPE csequence
      RETURNING VALUE(result) TYPE ty_t_measure.
    "! The columns of the cube's default drill-through action (RolapCube.getDefaultDrillThroughAction: the first
    "! DrillThroughAction with default="true"), in the order of the schema; empty: the cube has none.
    METHODS drill_through_columns
      IMPORTING cube          TYPE csequence
      RETURNING VALUE(result) TYPE ty_t_drill_column.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-DATA instance TYPE REF TO zzxxmla1_cl_schema.
    DATA catalog_names TYPE string_table.
    DATA all_cubes     TYPE ty_t_cube.
    DATA all_dims      TYPE ty_t_dim.
    DATA all_hiers     TYPE ty_t_hier.
    DATA all_levels    TYPE ty_t_level.
    DATA all_measures  TYPE ty_t_measure.
    DATA all_drill_columns TYPE ty_t_drill_column.
    TYPES:
      "! a dimension of a cube: its name in the cube and its definition
      BEGIN OF ty_cube_dimension,
        name TYPE string,
        def  TYPE zzxxmla1_cl_schema_def=>ty_dimension,
      END OF ty_cube_dimension,
      ty_t_cube_dimension TYPE STANDARD TABLE OF ty_cube_dimension WITH EMPTY KEY.

    "! The catalogs of the server: those of every data source of the repository, with their schema files. A catalog
    "! name is one catalog of the server: data sources may list it again with the same Definition.
    CLASS-METHODS find_catalogs
      RETURNING VALUE(result) TYPE ty_t_catalog
      RAISING   zzxxmla1_cx_xmla.
    "! A schema load error as the reference reports it in a SOAP fault.
    CLASS-METHODS fail
      IMPORTING !message TYPE string
      RAISING   zzxxmla1_cx_xmla.
    METHODS add_catalog
      IMPORTING catalog TYPE ty_catalog
      RAISING   zzxxmla1_cx_xmla.
    METHODS add_cube
      IMPORTING !schema   TYPE zzxxmla1_cl_schema_def=>ty_schema
                cube      TYPE zzxxmla1_cl_schema_def=>ty_cube
                catalog   TYPE string
                updated   TYPE timestampl
      RAISING   zzxxmla1_cx_xmla.
    METHODS add_dimension
      IMPORTING cube               TYPE string
                name               TYPE string
                caption            TYPE string
                foreign_key        TYPE string
                dimension          TYPE zzxxmla1_cl_schema_def=>ty_dimension
                members_with_facts TYPE abap_bool
      RAISING   zzxxmla1_cx_xmla.
    "! The value of a cube's annotation that is true or false (c_omit_empty_cells); false without it. Fails on another
    "! value.
    CLASS-METHODS cube_flag
      IMPORTING annotations   TYPE REF TO zzxxmla1_cl_schema_def=>ty_annotations
                name          TYPE string
                cube_name     TYPE string
      RETURNING VALUE(result) TYPE abap_bool
      RAISING   zzxxmla1_cx_xmla.
    "! The value of c_members_with_facts: the usage's annotation if it has one, else the dimension's; false without
    "! either. Fails on a value other than true or false.
    CLASS-METHODS members_with_facts
      IMPORTING usage         TYPE REF TO zzxxmla1_cl_schema_def=>ty_annotations OPTIONAL
                dimension     TYPE REF TO zzxxmla1_cl_schema_def=>ty_annotations OPTIONAL
                dim_name      TYPE string
      RETURNING VALUE(result) TYPE abap_bool
      RAISING   zzxxmla1_cx_xmla.
    "! The drill-through actions of a cube (RolapCube.addActions), each column resolved as the reference resolves it
    "! when it loads the schema; the columns of the first default one are kept.
    METHODS add_actions
      IMPORTING cube       TYPE string
                actions    TYPE zzxxmla1_cl_schema_def=>ty_t_node
                dimensions TYPE ty_t_cube_dimension
      RAISING   zzxxmla1_cx_xmla.
    "! A Hierarchy element of a dimension (RolapHierarchy, RolapLevel.createFromXml).
    METHODS add_hierarchy
      IMPORTING cube      TYPE string
                dim_name  TYPE string
                dimension TYPE zzxxmla1_cl_schema_def=>ty_dimension
                hierarchy TYPE zzxxmla1_cl_schema_def=>ty_hierarchy
                position  TYPE i
      RAISING   zzxxmla1_cx_xmla.
    "! A Hierarchy element annotated c_bw_hierarchy: the copy of the BW hierarchy it names and its levels by depth.
    METHODS add_bw_hierarchy
      IMPORTING hier      TYPE ty_hier
                dimension TYPE zzxxmla1_cl_schema_def=>ty_dimension
                hierarchy TYPE zzxxmla1_cl_schema_def=>ty_hierarchy
                bw_name   TYPE string
      RAISING   zzxxmla1_cx_xmla.
    "! The value of an annotation, initial without it.
    CLASS-METHODS annotation
      IMPORTING annotations   TYPE REF TO zzxxmla1_cl_schema_def=>ty_annotations
                name          TYPE string
      RETURNING VALUE(result) TYPE string.
    "! Adds a hierarchy; fails if the dimension has one of that name already.
    METHODS append_hierarchy
      IMPORTING hierarchy TYPE ty_hier
      RAISING   zzxxmla1_cx_xmla.
    "! The reference's name of the All member: "All " + the hierarchy's name (Dimension.Hierarchy, the dimension's
    "! hierarchy its name) + "s".
    CLASS-METHODS all_member_name
      IMPORTING dim_name      TYPE string
                hier_name     TYPE string
      RETURNING VALUE(result) TYPE string.
    "! A levelType as the reference reads it (RolapLevel.toLevelType): empty is Regular, TimeHalfYear is TimeHalfYears
    "! (ZZXXMLA1_CL_SCHEMA_DEF accepts only names of LevelType).
    CLASS-METHODS level_type
      IMPORTING level_type    TYPE string
      RETURNING VALUE(result) TYPE string.
    "! LevelType.isTime: TimeYears to TimeUndefined.
    CLASS-METHODS is_time
      IMPORTING level_type    TYPE string
      RETURNING VALUE(result) TYPE abap_bool.
    "! The type of a dimension whose levels are read (RolapDimension): the given one, without one the type of the first
    "! level; fails if a level's type does not fit (NonTimeLevelInTimeHierarchy, TimeLevelInNonTimeHierarchy).
    METHODS check_level_types
      IMPORTING cube          TYPE string
                dim_name      TYPE string
                dim_type      TYPE string
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_xmla.
    "! The member properties of a level (RolapLevel.createProperties): a sourceAttribute gives the column and the type
    "! (the property's type is ignored), else the property's column and type.
    METHODS level_properties
      IMPORTING level         TYPE zzxxmla1_cl_schema_def=>ty_level
                dimension     TYPE zzxxmla1_cl_schema_def=>ty_dimension
                location      TYPE string
      RETURNING VALUE(result) TYPE ty_t_property
      RAISING   zzxxmla1_cx_xmla.
    "! The column that names an attribute's members: its NameColumn, else its KeyColumn.
    CLASS-METHODS attribute_name_column
      IMPORTING attribute     TYPE zzxxmla1_cl_schema_def=>ty_dimension_attribute
      RETURNING VALUE(result) TYPE string.
    "! The column an attribute's members are ordered by (RolapDimension.resolveOrdinalColumn): its OrderByColumn, else
    "! the column orderBy names (Key, Name); initial if that is the key column or there is none.
    CLASS-METHODS attribute_ordinal_column
      IMPORTING attribute     TYPE zzxxmla1_cl_schema_def=>ty_dimension_attribute
      RETURNING VALUE(result) TYPE string.
    "! A column type as the type of a level: Numeric or String.
    CLASS-METHODS data_type
      IMPORTING column_type TYPE string
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zzxxmla1_cl_schema IMPLEMENTATION.

  METHOD get.
    IF instance IS NOT BOUND.
      instance = of_catalogs( find_catalogs( ) ).
    ENDIF.
    result = instance.
  ENDMETHOD.

  METHOD of_catalogs.
    result = NEW #( ).
    LOOP AT catalogs INTO DATA(catalog).
      result->add_catalog( catalog ).
    ENDLOOP.
    SORT result->catalog_names ASCENDING.
    SORT result->all_cubes BY catalog_name ASCENDING cube_name ASCENDING.
  ENDMETHOD.

  METHOD find_catalogs.
    DATA definitions TYPE string_table.
    LOOP AT zzxxmla1_cl_repository=>get( )->data_sources( ) INTO DATA(data_source).
      LOOP AT data_source-catalogs INTO DATA(catalog).
        READ TABLE result WITH KEY name = catalog-name TRANSPORTING NO FIELDS.
        IF sy-subrc = 0.
          IF definitions[ sy-tabix ] <> catalog-definition.
            fail( |Catalog '{ catalog-name }' has another Definition in data source '{ data_source-name }'| ).
          ENDIF.
          CONTINUE.
        ENDIF.
        DATA(file) = zzxxmla1_cl_files=>read( catalog-definition ).
        IF file-path IS INITIAL.
          fail( |Error while loading catalog '{ catalog-name }': the schema file { catalog-definition } does not exist| ).
        ENDIF.
        APPEND VALUE #( name = catalog-name schema = file-content updated_at = file-changed_at ) TO result.
        APPEND catalog-definition TO definitions.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD fail.
    zzxxmla1_cx_xmla=>raise_code( kind = `Server` code = `00HSBB01` text = `XMLA SOAP Body processing error`
                                  description = |olap4abap Error:{ message }| ).
  ENDMETHOD.

  METHOD add_catalog.
    DATA(name) = catalog-name.
    DATA schema TYPE zzxxmla1_cl_schema_def=>ty_schema.
    TRY.
        schema = zzxxmla1_cl_schema_def=>parse( catalog-schema ).
      CATCH zzxxmla1_cx_xom INTO DATA(error).
        fail( |Error while loading catalog '{ name }': { error->error_message }| ).
    ENDTRY.
    IF schema-virtual_cubes IS NOT INITIAL OR schema-roles IS NOT INITIAL OR schema-user_defined_functions IS NOT INITIAL
        OR schema-named_sets IS NOT INITIAL OR schema-parameters IS NOT INITIAL.
      fail( |Catalog '{ name }': virtual cubes, roles, user-defined functions, named sets and parameters | &&
            |are not supported| ).
    ENDIF.
    APPEND name TO catalog_names.
    LOOP AT schema-cubes INTO DATA(cube) WHERE enabled <> abap_false.
      add_cube( schema = schema cube = cube catalog = name updated = catalog-updated_at ).
    ENDLOOP.
  ENDMETHOD.

  METHOD add_cube.
    IF cube-fact-name <> `Table`.
      fail( |Cube '{ cube-name }': the fact must be a Table| ).
    ENDIF.
    IF line_exists( all_cubes[ cube_name = cube-name ] ).
      fail( |Cube '{ cube-name }' is defined twice| ).
    ENDIF.
    DATA(fact) = CAST zzxxmla1_cl_schema_def=>ty_table( cube-fact-def ).
    APPEND VALUE #( cube_name    = cube-name
                    catalog_name = catalog
                    caption      = COND #( WHEN cube-caption IS NOT INITIAL THEN cube-caption ELSE cube-name )
                    fact_table   = fact->name
                    generated_at = updated
                    omit_empty_cells = cube_flag( annotations = cube-annotations name = c_omit_empty_cells
                                                  cube_name   = cube-name ) ) TO all_cubes.

    DATA dimensions TYPE ty_t_cube_dimension.
    LOOP AT cube-dimensions INTO DATA(node).
      CASE node-name.
        WHEN `DimensionUsage`.
          DATA(usage) = CAST zzxxmla1_cl_schema_def=>ty_dimension_usage( node-def ).
          READ TABLE schema-dimensions INTO DATA(shared) WITH KEY name = usage->source.
          IF sy-subrc <> 0.
            fail( |Cube '{ cube-name }': shared dimension '{ usage->source }' not found| ).
          ENDIF.
          add_dimension( cube        = cube-name
                         name        = usage->name
                         caption     = COND #( WHEN usage->caption IS NOT INITIAL THEN usage->caption
                                               WHEN shared-caption IS NOT INITIAL THEN shared-caption
                                               ELSE usage->name )
                         foreign_key = usage->foreign_key
                         dimension   = shared
                         members_with_facts = members_with_facts( usage     = usage->annotations
                                                                  dimension = shared-annotations
                                                                  dim_name  = usage->name ) ).
          APPEND VALUE #( name = usage->name def = shared ) TO dimensions.
        WHEN `Dimension`.
          DATA(private) = CAST zzxxmla1_cl_schema_def=>ty_dimension( node-def ).
          add_dimension( cube        = cube-name
                         name        = private->name
                         caption     = COND #( WHEN private->caption IS NOT INITIAL THEN private->caption
                                               ELSE private->name )
                         foreign_key = private->foreign_key
                         dimension   = private->*
                         members_with_facts = members_with_facts( dimension = private->annotations
                                                                  dim_name  = private->name ) ).
          APPEND VALUE #( name = private->name def = private->* ) TO dimensions.
        WHEN OTHERS.
          fail( |Cube '{ cube-name }': { node-name } is not supported| ).
      ENDCASE.
    ENDLOOP.

    LOOP AT cube-measures INTO DATA(measure).
      IF measure-column IS INITIAL.
        fail( |Measure '{ measure-name }': only measures on a column are supported| ).
      ENDIF.
      APPEND VALUE #( cube_name     = cube-name
                      meas_name     = measure-name
                      seq_no        = sy-tabix
                      caption       = COND #( WHEN measure-caption IS NOT INITIAL THEN measure-caption ELSE measure-name )
                      fact_column   = measure-column
                      aggregator    = measure-aggregator
                      format_string = measure-format_string
                      visible       = xsdbool( measure-visible <> abap_false ) ) TO all_measures.
    ENDLOOP.
    add_actions( cube = cube-name actions = cube-actions dimensions = dimensions ).
  ENDMETHOD.

  METHOD add_actions.
    DATA(kept) = abap_false.
    LOOP AT actions INTO DATA(node) WHERE name = `DrillThroughAction`.
      DATA(action) = CAST zzxxmla1_cl_schema_def=>ty_drill_through_action( node-def ).
      DATA(columns) = VALUE ty_t_drill_column( ).
      LOOP AT action->columns INTO DATA(column_node).
        DATA(column) = VALUE ty_drill_column( cube_name = cube ).
        IF column_node-name = `DrillThroughMeasure`.
          DATA(measure) = CAST zzxxmla1_cl_schema_def=>ty_drill_through_measure( column_node-def ).
          IF NOT line_exists( all_measures[ cube_name = cube meas_name = measure->measure ] ).
            fail( |Error while creating DrillThrough  action. Measure '{ measure->name }' not found| ).
          ENDIF.
          column-name = measure->name.
          column-meas_name = measure->measure.
          APPEND column TO columns.
          CONTINUE.
        ENDIF.
        DATA(attribute) = CAST zzxxmla1_cl_schema_def=>ty_drill_through_attribute( column_node-def ).
        column-name = attribute->name.
        column-dim_name = attribute->dimension.
        READ TABLE dimensions INTO DATA(dimension) WITH KEY name = attribute->dimension.
        IF sy-subrc <> 0.
          fail( |Error while creating DrillThrough  action. Dimension '{ attribute->dimension }' not found| ).
        ENDIF.
        IF attribute->source_attribute IS NOT INITIAL.
          " resolveDrillThroughAttributeColumn: the key column of the dimension's attribute, whatever hierarchy it has
          READ TABLE dimension-def-attributes INTO DATA(source) WITH KEY name = attribute->source_attribute.
          IF sy-subrc <> 0 OR source-key_column IS NOT BOUND.
            fail( |Error while creating DrillThrough  action. Attribute '{ attribute->source_attribute }' | &&
                  |not found on dimension '{ attribute->dimension }'| ).
          ENDIF.
          column-column = source-key_column->column_name.
        ELSEIF attribute->hierarchy IS NOT INITIAL.
          " a level is looked for only in a named hierarchy
          IF NOT line_exists( all_hiers[ cube_name = cube dim_name = attribute->dimension
                                         hier_name = attribute->hierarchy ] ).
            fail( |Error while creating DrillThrough  action. Hierarchy '{ attribute->hierarchy }' not found| ).
          ENDIF.
          column-hier_name = attribute->hierarchy.
          IF attribute->level IS NOT INITIAL.
            IF NOT line_exists( all_levels[ cube_name = cube dim_name = attribute->dimension
                                            hier_name = attribute->hierarchy level_name = attribute->level ] ).
              fail( |Error while creating DrillThrough  action. Level '{ attribute->level }' not found| ).
            ENDIF.
            column-level_name = attribute->level.
          ENDIF.
        ENDIF.
        APPEND column TO columns.
      ENDLOOP.
      IF action->_default = abap_true AND kept = abap_false.
        APPEND LINES OF columns TO all_drill_columns.
        kept = abap_true.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD add_dimension.
    IF dimension-table IS INITIAL.
      fail( |Dimension '{ name }': a dimension needs a table| ).
    ENDIF.
    READ TABLE dimension-attributes INTO DATA(key) WITH KEY usage = `Key`.
    IF sy-subrc <> 0 OR key-key_column IS NOT BOUND.
      fail( |Dimension '{ name }': no key attribute| ).
    ENDIF.
    APPEND VALUE #( cube_name  = cube
                    dim_name   = name
                    seq_no     = 1 + REDUCE i( INIT n = 0 FOR d IN all_dims WHERE ( cube_name = cube ) NEXT n = n + 1 )
                    caption    = caption
                    fk_column  = foreign_key
                    dim_table  = dimension-table
                    key_column = key-key_column->column_name
                    members_with_facts = members_with_facts )
           TO all_dims ASSIGNING FIELD-SYMBOL(<dim>).

    " RolapDimension: the hierarchies of the Hierarchy elements, then one per attribute
    DATA(position) = 0.
    LOOP AT dimension-hierarchies INTO DATA(hierarchy).
      position = position + 1.
      add_hierarchy( cube = cube dim_name = name dimension = dimension hierarchy = hierarchy position = position ).
    ENDLOOP.
    LOOP AT dimension-attributes INTO DATA(attribute) WHERE attribute_hierarchy_enabled <> abap_false.
      IF attribute-key_column IS NOT BOUND.
        fail( |Attribute '{ attribute-name }' of dimension '{ name }' has no key column| ).
      ENDIF.
      position = position + 1.
      DATA(hier_name) = attribute-name.
      append_hierarchy( VALUE #( cube_name       = cube
                                 dim_name        = name
                                 hier_name       = hier_name
                                 name            = |{ name }.{ hier_name }|
                                 seq_no          = position
                                 caption         = hier_name
                                 has_all         = abap_true
                                 all_member_name = all_member_name( dim_name = name hier_name = hier_name )
                                 default_member  = attribute-default_member
                                 origin          = COND #( WHEN attribute-usage = `Key` THEN 6 ELSE 2 ) ) ).
      APPEND VALUE #( cube_name      = cube
                      dim_name       = name
                      hier_name      = hier_name
                      level_no       = 1
                      level_name     = hier_name
                      caption        = hier_name
                      key_column     = attribute-key_column->column_name
                      name_column    = attribute_name_column( attribute )
                      ordinal_column = attribute_ordinal_column( attribute )
                      data_type      = data_type( attribute-key_column->data_type )
                      unique_members = abap_true
                      level_type     = level_type( attribute-level_type ) ) TO all_levels.
    ENDLOOP.
    <dim>-dim_type = check_level_types( cube = cube dim_name = name dim_type = dimension-type ).
    IF <dim>-dim_type = `Time` AND members_with_facts = abap_true.
      fail( |Dimension '{ name }': { c_members_with_facts } is not supported on a time dimension| ).
    ENDIF.
  ENDMETHOD.

  METHOD cube_flag.
    IF annotations IS NOT BOUND.
      RETURN.
    ENDIF.
    READ TABLE annotations->array INTO DATA(annotation) WITH KEY name = name.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    DATA(value) = condense( to_lower( annotation-cdata ) ).
    IF value <> `true` AND value <> `false`.
      fail( |Cube '{ cube_name }': the annotation { name } must be true or false| ).
    ENDIF.
    result = xsdbool( value = `true` ).
  ENDMETHOD.

  METHOD members_with_facts.
    DATA(value) = VALUE string( ).
    DATA(found) = abap_false.
    LOOP AT VALUE zzxxmla1_cl_schema_def=>ty_t_annotations( ( COND #( WHEN usage IS BOUND THEN usage->* ) )
                                                             ( COND #( WHEN dimension IS BOUND THEN dimension->* ) ) )
         INTO DATA(annotations).
      READ TABLE annotations-array INTO DATA(annotation) WITH KEY name = c_members_with_facts.
      IF sy-subrc = 0.
        value = condense( to_lower( annotation-cdata ) ).
        found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF found = abap_false.
      RETURN.
    ENDIF.
    IF value <> `true` AND value <> `false`.
      fail( |Dimension '{ dim_name }': the annotation { c_members_with_facts } must be true or false| ).
    ENDIF.
    result = xsdbool( value = `true` ).
  ENDMETHOD.

  METHOD add_hierarchy.
    DATA(hier_name) = COND string( WHEN hierarchy-name IS NOT INITIAL THEN hierarchy-name ELSE dim_name ).
    DATA(where) = |Hierarchy '{ hier_name }' of dimension '{ dim_name }'|.
    IF hierarchy-relation IS NOT INITIAL OR hierarchy-member_reader_class IS NOT INITIAL.
      fail( |{ where }: only the table of the dimension is supported| ).
    ENDIF.
    DATA(hier) = VALUE ty_hier( cube_name       = cube
                                dim_name        = dim_name
                                hier_name       = hier_name
                                name            = COND #( WHEN hierarchy-name IS INITIAL THEN dim_name
                                                          ELSE |{ dim_name }.{ hier_name }| )
                                seq_no          = position
                                caption         = COND #( WHEN hierarchy-caption IS NOT INITIAL THEN hierarchy-caption
                                                          ELSE hier_name )
                                has_all         = hierarchy-has_all
                                all_member_name = COND #( WHEN hierarchy-all_member_name IS NOT INITIAL
                                                          THEN hierarchy-all_member_name
                                                          ELSE all_member_name( dim_name = dim_name hier_name = hier_name ) )
                                default_member  = hierarchy-default_member
                                origin          = 1 ).
    DATA(bw_name) = condense( annotation( annotations = hierarchy-annotations name = c_bw_hierarchy ) ).
    IF bw_name IS NOT INITIAL.
      add_bw_hierarchy( hier = hier dimension = dimension hierarchy = hierarchy bw_name = bw_name ).
      RETURN.
    ENDIF.
    IF hierarchy-levels IS INITIAL.
      fail( |{ where }: a hierarchy needs levels| ).
    ENDIF.
    append_hierarchy( hier ).

    LOOP AT hierarchy-levels INTO DATA(level).
      DATA(level_no) = sy-tabix.
      IF level-parent_column IS NOT INITIAL OR level-parent_exp IS BOUND OR level-closure IS BOUND
          OR level-key_exp IS BOUND OR level-name_exp IS BOUND
          OR level-caption_exp IS BOUND OR level-ordinal_exp IS BOUND OR level-caption_column IS NOT INITIAL
          OR level-member_formatter IS BOUND OR level-formatter IS NOT INITIAL
          OR ( level-hide_member_if IS NOT INITIAL AND level-hide_member_if <> `Never` )
          OR ( level-table IS NOT INITIAL AND level-table <> dimension-table ).
        fail( |{ where }, level '{ level-name }': only a key column, a name column and an ordinal column of the | &&
              |dimension's table are supported| ).
      ENDIF.
      DATA(key_column) = level-column.
      DATA(name_column) = level-name_column.
      DATA(ordinal_column) = level-ordinal_column.
      DATA(type) = level-type.
      IF level-source_attribute IS NOT INITIAL.
        " RolapLevel.createFromXml: the attribute gives the key column and its type
        READ TABLE dimension-attributes INTO DATA(attribute) WITH KEY name = level-source_attribute.
        IF sy-subrc <> 0 OR attribute-key_column IS NOT BOUND.
          fail( |sourceAttribute '{ level-source_attribute }' not found for level '{ level-name }'| ).
        ENDIF.
        key_column = attribute-key_column->column_name.
        type = attribute-key_column->data_type.
        IF name_column IS INITIAL AND attribute-name_column IS BOUND.
          name_column = attribute-name_column->column_name.
        ENDIF.
        " RolapLevel: the attribute's OrderByColumn is the level's ordinal
        IF attribute-order_by_column IS BOUND.
          ordinal_column = attribute-order_by_column->column_name.
        ENDIF.
      ENDIF.
      IF key_column IS INITIAL.
        fail( |{ where }, level '{ level-name }': a level needs a column or a sourceAttribute| ).
      ENDIF.
      APPEND VALUE #( cube_name      = cube
                      dim_name       = dim_name
                      hier_name      = hier_name
                      level_no       = level_no
                      level_name     = level-name
                      caption        = COND #( WHEN level-caption IS NOT INITIAL THEN level-caption ELSE level-name )
                      key_column     = key_column
                      name_column    = COND #( WHEN name_column IS NOT INITIAL THEN name_column ELSE key_column )
                      ordinal_column = COND #( WHEN ordinal_column <> key_column THEN ordinal_column )
                      data_type      = data_type( type )
                      unique_members = level-unique_members
                      level_type     = level_type( level-level_type )
                      properties     = level_properties( level = level dimension = dimension
                                                         location = |{ where }, level '{ level-name }'| ) ) TO all_levels.
    ENDLOOP.
  ENDMETHOD.

  METHOD add_bw_hierarchy.
    DATA(where) = |Hierarchy '{ hier-hier_name }' of dimension '{ hier-dim_name }'|.
    IF hierarchy-levels IS NOT INITIAL.
      fail( |{ where }: a BW hierarchy ({ c_bw_hierarchy }) has no levels, they are made from its depth| ).
    ENDIF.
    DATA(characteristic) = zzxxmla1_cl_bw_view_gen=>characteristic_of_view( dimension-table ).
    IF characteristic IS INITIAL.
      fail( |{ where }: the BW hierarchy { bw_name } needs the view of a characteristic as the dimension's table, | &&
            |not { dimension-table }| ).
    ENDIF.
    READ TABLE dimension-attributes INTO DATA(key) WITH KEY usage = `Key`.
    DATA(row) = hier.
    TRY.
        row-bw_hierarchy = NEW zzxxmla1_cl_bw_hierarchy_copy( )->current( characteristic = CONV #( characteristic )
                                                                          name           = CONV #( bw_name ) ).
        DATA(depth) = zzxxmla1_cl_bw_hierarchy_copy=>depth( row-bw_hierarchy ).
      CATCH zzxxmla1_cx_bw_hierarchy INTO DATA(error).
        fail( |{ where }: { error->get_text( ) }| ).
    ENDTRY.
    append_hierarchy( row ).
    " a member's key is its SID: a node's negative one, a value's the characteristic's (the key column of the view)
    DO depth TIMES.
      DATA(level_name) = |{ c_bw_level_prefix }{ sy-index WIDTH = 2 ALIGN = RIGHT PAD = `0` }|.
      APPEND VALUE #( cube_name      = hier-cube_name
                      dim_name       = hier-dim_name
                      hier_name      = hier-hier_name
                      level_no       = sy-index
                      level_name     = level_name
                      caption        = level_name
                      key_column     = key-key_column->column_name
                      name_column    = key-key_column->column_name
                      data_type      = `Numeric`
                      unique_members = abap_true
                      level_type     = `Regular` ) TO all_levels.
    ENDDO.
  ENDMETHOD.

  METHOD annotation.
    IF annotations IS NOT BOUND.
      RETURN.
    ENDIF.
    READ TABLE annotations->array INTO DATA(found) WITH KEY name = name.
    IF sy-subrc = 0.
      result = found-cdata.
    ENDIF.
  ENDMETHOD.

  METHOD level_properties.
    LOOP AT level-properties INTO DATA(property).
      DATA(property_where) = |{ location }, property '{ property-name }'|.
      IF property-formatter IS NOT INITIAL OR property-property_formatter IS BOUND.
        fail( |{ property_where }: property formatters are not supported| ).
      ENDIF.
      DATA(column) = property-column.
      DATA(type) = COND string( WHEN property-type IS NOT INITIAL THEN property-type ELSE `String` ).
      IF property-source_attribute IS NOT INITIAL.
        READ TABLE dimension-attributes INTO DATA(attribute) WITH KEY name = property-source_attribute.
        IF sy-subrc <> 0 OR attribute-key_column IS NOT BOUND.
          fail( |sourceAttribute '{ property-source_attribute }' not found for property '{ property-name }' | &&
                |of level '{ level-name }'| ).
        ENDIF.
        column = attribute-key_column->column_name.
        type = COND #( WHEN attribute-key_column->data_type IS NOT INITIAL THEN attribute-key_column->data_type
                       ELSE `String` ).
      ENDIF.
      IF column IS INITIAL.
        fail( |Property '{ property-name }' of level '{ level-name }' must have either sourceAttribute or column| ).
      ENDIF.
      " RolapLevel.convertPropertyTypeNameToCode; the date and time types are not supported
      IF type <> `String` AND type <> `Numeric` AND type <> `Integer` AND type <> `Long` AND type <> `Boolean`.
        fail( |{ property_where }: the type { type } is not supported| ).
      ENDIF.
      APPEND VALUE #( name      = property-name
                      caption   = COND #( WHEN property-caption IS NOT INITIAL THEN property-caption
                                          ELSE property-name )
                      column    = column
                      data_type = type ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD append_hierarchy.
    READ TABLE all_hiers INTO DATA(existing) WITH KEY cube_name = hierarchy-cube_name dim_name = hierarchy-dim_name
                                                    hier_name = hierarchy-hier_name.
    IF sy-subrc = 0.
      " The reference server gives both the same unique name; the hierarchies of Hierarchy elements come first
      IF existing-origin = 1 AND hierarchy-origin <> 1 AND existing-name = hierarchy-dim_name.
        fail( |Dimension '{ hierarchy-dim_name }': hierarchy '{ hierarchy-hier_name }' is defined twice, | &&
              |by an unnamed Hierarchy and by the attribute '{ hierarchy-hier_name }'; name the Hierarchy| ).
      ENDIF.
      fail( |Dimension '{ hierarchy-dim_name }': hierarchy '{ hierarchy-hier_name }' is defined twice| ).
    ENDIF.
    APPEND hierarchy TO all_hiers.
  ENDMETHOD.

  METHOD all_member_name.
    result = |All { COND string( WHEN hier_name = dim_name THEN dim_name ELSE |{ dim_name }.{ hier_name }| ) }s|.
  ENDMETHOD.

  METHOD level_type.
    result = COND #( WHEN level_type IS INITIAL THEN `Regular`
                     WHEN level_type = `TimeHalfYear` THEN `TimeHalfYears`
                     ELSE level_type ).
  ENDMETHOD.

  METHOD is_time.
    result = xsdbool( level_type CP `Time*` ).
  ENDMETHOD.

  METHOD check_level_types.
    " RolapLevel checks a level against a given dimension type, RolapDimension the levels of an untyped dimension
    " against its first level; the hierarchies' levels in the order of the dimension, the (All) levels left out
    result = COND #( WHEN dim_type = `TimeDimension` THEN `Time` WHEN dim_type = `StandardDimension` THEN `Standard` ).
    LOOP AT all_hiers INTO DATA(hier) WHERE cube_name = cube AND dim_name = dim_name.
      LOOP AT all_levels INTO DATA(level)
           WHERE cube_name = cube AND dim_name = dim_name AND hier_name = hier-hier_name.
        DATA(time_level) = is_time( level-level_type ).
        IF result IS INITIAL.
          result = COND #( WHEN time_level = abap_true THEN `Time` ELSE `Standard` ).
        ELSEIF result = `Time` AND time_level = abap_false.
          fail( |Level '[{ hier-name }].[{ level-level_name }]' belongs to a time hierarchy, so its level-type must be | &&
                | 'Years', 'Quarters', 'Months', 'Weeks' or 'Days'.| ).
        ELSEIF result = `Standard` AND time_level = abap_true.
          fail( |Level '[{ hier-name }].[{ level-level_name }]' does not belong to a time hierarchy, so its level-type | &&
                |must be 'Standard'.| ).
        ENDIF.
      ENDLOOP.
    ENDLOOP.
    IF result IS INITIAL.
      result = `Standard`.
    ENDIF.
  ENDMETHOD.

  METHOD attribute_name_column.
    result = COND #( WHEN attribute-name_column IS BOUND THEN attribute-name_column->column_name
                     ELSE attribute-key_column->column_name ).
  ENDMETHOD.

  METHOD attribute_ordinal_column.
    IF attribute-order_by_column IS BOUND.
      result = attribute-order_by_column->column_name.
    ELSEIF attribute-order_by = `Name`.
      result = attribute_name_column( attribute ).
    ENDIF.
    IF attribute-key_column IS BOUND AND result = attribute-key_column->column_name.
      CLEAR result.
    ENDIF.
  ENDMETHOD.

  METHOD data_type.
    result = COND #( WHEN column_type = `Integer` OR column_type = `Numeric` THEN `Numeric` ELSE `String` ).
  ENDMETHOD.

  METHOD catalogs.
    result = catalog_names.
  ENDMETHOD.

  METHOD cubes.
    result = all_cubes.
  ENDMETHOD.

  METHOD dimensions.
    result = VALUE #( FOR d IN all_dims WHERE ( cube_name = cube ) ( d ) ).
  ENDMETHOD.

  METHOD hierarchies.
    result = VALUE #( FOR h IN all_hiers WHERE ( cube_name = cube AND dim_name = dim ) ( h ) ).
  ENDMETHOD.

  METHOD levels.
    result = VALUE #( FOR l IN all_levels WHERE ( cube_name = cube AND dim_name = dim AND hier_name = hier ) ( l ) ).
  ENDMETHOD.

  METHOD drill_through_columns.
    result = VALUE #( FOR c IN all_drill_columns WHERE ( cube_name = cube ) ( c ) ).
  ENDMETHOD.

  METHOD measures.
    result = VALUE #( FOR m IN all_measures WHERE ( cube_name = cube ) ( m ) ).
  ENDMETHOD.

ENDCLASS.
