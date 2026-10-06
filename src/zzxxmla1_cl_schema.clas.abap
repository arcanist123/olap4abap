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

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-DATA instance TYPE REF TO zzxxmla1_cl_schema.
    DATA catalog_names TYPE string_table.
    DATA all_cubes     TYPE ty_t_cube.
    DATA all_dims      TYPE ty_t_dim.
    DATA all_hiers     TYPE ty_t_hier.
    DATA all_levels    TYPE ty_t_level.
    DATA all_measures  TYPE ty_t_measure.

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
      IMPORTING cube        TYPE string
                name        TYPE string
                caption     TYPE string
                foreign_key TYPE string
                dimension   TYPE zzxxmla1_cl_schema_def=>ty_dimension
      RAISING   zzxxmla1_cx_xmla.
    "! A Hierarchy element of a dimension (RolapHierarchy, RolapLevel.createFromXml).
    METHODS add_hierarchy
      IMPORTING cube      TYPE string
                dim_name  TYPE string
                dimension TYPE zzxxmla1_cl_schema_def=>ty_dimension
                hierarchy TYPE zzxxmla1_cl_schema_def=>ty_hierarchy
                position  TYPE i
      RAISING   zzxxmla1_cx_xmla.
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
                    generated_at = updated ) TO all_cubes.

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
                         dimension   = shared ).
        WHEN `Dimension`.
          DATA(private) = CAST zzxxmla1_cl_schema_def=>ty_dimension( node-def ).
          add_dimension( cube        = cube-name
                         name        = private->name
                         caption     = COND #( WHEN private->caption IS NOT INITIAL THEN private->caption
                                               ELSE private->name )
                         foreign_key = private->foreign_key
                         dimension   = private->* ).
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
                    key_column = key-key_column->column_name )
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
                      data_type      = data_type( attribute-key_column->data_type )
                      unique_members = abap_true
                      level_type     = level_type( attribute-level_type ) ) TO all_levels.
    ENDLOOP.
    <dim>-dim_type = check_level_types( cube = cube dim_name = name dim_type = dimension-type ).
  ENDMETHOD.

  METHOD add_hierarchy.
    DATA(hier_name) = COND string( WHEN hierarchy-name IS NOT INITIAL THEN hierarchy-name ELSE dim_name ).
    DATA(where) = |Hierarchy '{ hier_name }' of dimension '{ dim_name }'|.
    IF hierarchy-relation IS NOT INITIAL OR hierarchy-member_reader_class IS NOT INITIAL.
      fail( |{ where }: only the table of the dimension is supported| ).
    ENDIF.
    IF hierarchy-levels IS INITIAL.
      fail( |{ where }: a hierarchy needs levels| ).
    ENDIF.
    append_hierarchy( VALUE #( cube_name       = cube
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
                               origin          = 1 ) ).

    LOOP AT hierarchy-levels INTO DATA(level).
      DATA(level_no) = sy-tabix.
      IF level-parent_column IS NOT INITIAL OR level-parent_exp IS BOUND OR level-closure IS BOUND
          OR level-key_exp IS BOUND OR level-name_exp IS BOUND
          OR level-caption_exp IS BOUND OR level-ordinal_exp IS BOUND OR level-caption_column IS NOT INITIAL
          OR level-ordinal_column IS NOT INITIAL OR level-member_formatter IS BOUND OR level-formatter IS NOT INITIAL
          OR ( level-hide_member_if IS NOT INITIAL AND level-hide_member_if <> `Never` )
          OR ( level-table IS NOT INITIAL AND level-table <> dimension-table ).
        fail( |{ where }, level '{ level-name }': only a key column and a name column of the dimension's table | &&
              |are supported| ).
      ENDIF.
      DATA(key_column) = level-column.
      DATA(name_column) = level-name_column.
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
                      data_type      = data_type( type )
                      unique_members = level-unique_members
                      level_type     = level_type( level-level_type )
                      properties     = level_properties( level = level dimension = dimension
                                                         location = |{ where }, level '{ level-name }'| ) ) TO all_levels.
    ENDLOOP.
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

  METHOD measures.
    result = VALUE #( FOR m IN all_measures WHERE ( cube_name = cube ) ( m ) ).
  ENDMETHOD.

ENDCLASS.
