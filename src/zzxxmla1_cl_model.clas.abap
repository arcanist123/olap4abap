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
"! The model of a cube for the engine and the rowsets, taken from the cube's schema (ZZXXMLA1_CL_SCHEMA): the
"! hierarchies and measures of a cube and the members of a hierarchy, read from its dimension table with native SQL.
CLASS zzxxmla1_cl_model DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! A hierarchy of the model with what is needed to read its members and to join it to the fact table. The columns
    "! of its levels are columns of the dimension table.
    TYPES:
      BEGIN OF ty_hierarchy,
        dim_name        TYPE string,
        hier_name       TYPE string,
        name            TYPE string,   " The reference's name: Store for the dimension's unnamed hierarchy, else Store.Country
        unique_name     TYPE string,   " [Store] for the dimension's hierarchy, [Store.Country] for the others
        has_all         TYPE abap_bool,
        all_member_name TYPE string,
        default_member  TYPE string,   " unique name; empty: the All member, without one the first member
        levels          TYPE zzxxmla1_cl_schema=>ty_t_level,
        fk_column       TYPE string,   " column of the fact table
        dim_table       TYPE string,   " table (or view) of the dimension
        key_column      TYPE string,   " column of the dimension table the foreign key refers to
        dim_type        TYPE string,   " of the dimension: Standard or Time
      END OF ty_hierarchy,
      ty_t_hierarchy TYPE STANDARD TABLE OF ty_hierarchy WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_measure,
        name        TYPE string,
        fact_column TYPE string,
        aggregator  TYPE string,
        format      TYPE string,
      END OF ty_measure,
      ty_t_measure TYPE STANDARD TABLE OF ty_measure WITH EMPTY KEY.
    TYPES:
      "! A member of a hierarchy as read from the dimension table (the All member is not one of them).
      BEGIN OF ty_member,
        level_no    TYPE i,        " the level, from 1
        key         TYPE string,   " value of the level's key column
        name        TYPE string,
        path        TYPE string,   " the keys of the levels 1 to level_no, separated by c_separator
        unique_name TYPE string,   " the hierarchy's unique name, then the names from the first level
        parent      TYPE string,   " unique name of the parent; empty on the first level
        children    TYPE i,
        properties  TYPE string_table,  " the values of the level's member properties, in their order
      END OF ty_member,
      ty_t_member TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY.

    "! Separates the keys of a member's path.
    CONSTANTS c_separator TYPE c LENGTH 1 VALUE cl_abap_char_utilities=>horizontal_tab.

    "! MDX unique name of a hierarchy: [Dimension] for the hierarchy named like the dimension, [Dimension.Hierarchy]
    "! for the others.
    CLASS-METHODS hierarchy_unique_name
      IMPORTING dim_name      TYPE clike
                hier_name     TYPE clike
      RETURNING VALUE(result) TYPE string.
    "! The hierarchies of a cube in model order (dimensions by position, in each the hierarchies of the dimension in
    "! the order of the schema).
    CLASS-METHODS hierarchies
      IMPORTING cube          TYPE csequence
      RETURNING VALUE(result) TYPE ty_t_hierarchy
      RAISING   zzxxmla1_cx_xmla.
    "! The measures of a cube in the order of the schema, plus the count of the fact rows that the reference adds to every
    "! cube as a measure of its own.
    CLASS-METHODS measures
      IMPORTING cube          TYPE csequence
      RETURNING VALUE(result) TYPE ty_t_measure
      RAISING   zzxxmla1_cx_xmla.
    "! The members of a hierarchy in hierarchy order (a parent before its children, children by key), as the reference
    "! reads them: the distinct values of the level columns of the dimension table, ordered by the keys from the
    "! first level, with the columns of the levels' member properties (SqlMemberSource.makeChildMemberSql).
    CLASS-METHODS members
      IMPORTING hierarchy     TYPE ty_hierarchy
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The members of a level built from rows of the level columns: each row holds per level the key, followed by
    "! the name if the level has a name column of its own, then the values of the level's properties; the rows are in
    "! hierarchy order. A member's properties are the ones of its first row.
    CLASS-METHODS members_of_rows
      IMPORTING hierarchy     TYPE ty_hierarchy
                rows          TYPE zzxxmla1_cl_sql=>ty_t_row
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The number of members of a level as the reference counts it (SqlMemberSource.getLevelMemberCount): the distinct
    "! values of the level's column, or of the columns of the levels down to it if its members are not unique.
    CLASS-METHODS level_cardinality
      IMPORTING hierarchy     TYPE ty_hierarchy
                level_no      TYPE i
      RETURNING VALUE(result) TYPE i.
    "! The number of rows of a dimension table, or of the distinct values of one of its columns.
    CLASS-METHODS row_count
      IMPORTING table         TYPE csequence
                column        TYPE csequence OPTIONAL
      RETURNING VALUE(result) TYPE i.
    "! A value of a level column as the reference writes the member name: the key's text (Object.toString). Numbers come
    "! from the database as numbers (the characteristic views cast NUMC), so nothing is changed.
    CLASS-METHODS member_name
      IMPORTING value         TYPE string
                data_type     TYPE clike
      RETURNING VALUE(result) TYPE string.
    "! A name as a segment of a unique name: in brackets, a closing bracket doubled.
    CLASS-METHODS quote_name
      IMPORTING name          TYPE string
      RETURNING VALUE(result) TYPE string.
ENDCLASS.

CLASS zzxxmla1_cl_model IMPLEMENTATION.

  METHOD hierarchy_unique_name.
    result = COND #( WHEN hier_name = dim_name THEN |[{ dim_name }]| ELSE |[{ dim_name }.{ hier_name }]| ).
  ENDMETHOD.

  METHOD hierarchies.
    DATA(schema) = zzxxmla1_cl_schema=>get( ).
    LOOP AT schema->dimensions( cube ) INTO DATA(dim).
      LOOP AT schema->hierarchies( cube = cube dim = dim-dim_name ) INTO DATA(hier).
        APPEND VALUE #( dim_name        = dim-dim_name
                        hier_name       = hier-hier_name
                        name            = hier-name
                        unique_name     = hierarchy_unique_name( dim_name = dim-dim_name hier_name = hier-hier_name )
                        has_all         = hier-has_all
                        all_member_name = hier-all_member_name
                        default_member  = hier-default_member
                        levels          = schema->levels( cube = cube dim = dim-dim_name hier = hier-hier_name )
                        fk_column       = dim-fk_column
                        dim_table       = dim-dim_table
                        key_column      = dim-key_column
                        dim_type        = dim-dim_type ) TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD measures.
    LOOP AT zzxxmla1_cl_schema=>get( )->measures( cube ) INTO DATA(measure).
      APPEND VALUE #( name = measure-meas_name fact_column = measure-fact_column aggregator = measure-aggregator
                      format = measure-format_string ) TO result.
    ENDLOOP.
    APPEND VALUE #( name = `Fact Count` aggregator = `count` ) TO result.
  ENDMETHOD.

  METHOD members.
    DATA(columns) = VALUE string_table( ).
    DATA(order_by) = VALUE string_table( ).
    LOOP AT hierarchy-levels INTO DATA(level).
      APPEND zzxxmla1_cl_sql=>quote( level-key_column ) TO columns.
      APPEND zzxxmla1_cl_sql=>quote( level-key_column ) TO order_by.
      IF level-name_column <> level-key_column.
        APPEND zzxxmla1_cl_sql=>quote( level-name_column ) TO columns.
      ENDIF.
      LOOP AT level-properties INTO DATA(property).
        APPEND zzxxmla1_cl_sql=>quote( property-column ) TO columns.
      ENDLOOP.
    ENDLOOP.
    DATA(rows) = zzxxmla1_cl_sql=>query(
      sql     = |SELECT DISTINCT { concat_lines_of( table = columns sep = `, ` ) } | &&
                |FROM { zzxxmla1_cl_sql=>quote( hierarchy-dim_table ) } | &&
                |ORDER BY { concat_lines_of( table = order_by sep = `, ` ) }|
      columns = lines( columns ) ).
    result = members_of_rows( hierarchy = hierarchy rows = rows ).
  ENDMETHOD.

  METHOD members_of_rows.
    TYPES:
      BEGIN OF ty_count,
        parent TYPE string,
        count  TYPE i,
      END OF ty_count.
    DATA counts TYPE HASHED TABLE OF ty_count WITH UNIQUE KEY parent.
    DATA last_paths TYPE string_table.
    DATA(depth) = lines( hierarchy-levels ).
    last_paths = VALUE #( FOR i = 1 UNTIL i > depth ( ) ).

    LOOP AT rows INTO DATA(row).
      DATA(first_row) = xsdbool( sy-tabix = 1 ).
      DATA(column) = 0.
      DATA(path) = VALUE string( ).
      DATA(parent) = VALUE string( ).
      DATA(parent_unique) = hierarchy-unique_name.
      LOOP AT hierarchy-levels INTO DATA(level).
        DATA(level_no) = sy-tabix.
        column = column + 1.
        DATA(key) = row[ column ].
        DATA(name) = member_name( value = key data_type = level-data_type ).
        IF level-name_column <> level-key_column.
          column = column + 1.
          name = row[ column ].
        ENDIF.
        DATA(properties) = VALUE string_table( ).
        DO lines( level-properties ) TIMES.
          column = column + 1.
          APPEND row[ column ] TO properties.
        ENDDO.
        path = COND #( WHEN level_no = 1 THEN key ELSE path && c_separator && key ).
        DATA(unique_name) = parent_unique && `.` && quote_name( name ).
        " a new member when the keys down to this level differ from the previous row's
        IF first_row = abap_true OR path <> last_paths[ level_no ].
          last_paths[ level_no ] = path.
          APPEND VALUE #( level_no = level_no key = key name = name path = path unique_name = unique_name
                          parent = parent properties = properties ) TO result.
          IF parent IS NOT INITIAL.
            ASSIGN counts[ parent = parent ] TO FIELD-SYMBOL(<count>).
            IF sy-subrc = 0.
              <count>-count = <count>-count + 1.
            ELSE.
              INSERT VALUE #( parent = parent count = 1 ) INTO TABLE counts.
            ENDIF.
          ENDIF.
        ENDIF.
        parent = unique_name.
        parent_unique = unique_name.
      ENDLOOP.
    ENDLOOP.

    LOOP AT result ASSIGNING FIELD-SYMBOL(<member>).
      ASSIGN counts[ parent = <member>-unique_name ] TO <count>.
      IF sy-subrc = 0.
        <member>-children = <count>-count.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD level_cardinality.
    DATA(level) = hierarchy-levels[ level_no ].
    DATA(table) = zzxxmla1_cl_sql=>quote( hierarchy-dim_table ).
    IF level-unique_members = abap_true OR level_no = 1.
      result = row_count( table = hierarchy-dim_table column = level-key_column ).
      RETURN.
    ENDIF.
    DATA(columns) = VALUE string_table( ).
    LOOP AT hierarchy-levels INTO DATA(upper) TO level_no.
      APPEND zzxxmla1_cl_sql=>quote( upper-key_column ) TO columns.
    ENDLOOP.
    DATA(rows) = zzxxmla1_cl_sql=>query(
      sql     = |SELECT COUNT( * ) FROM ( SELECT DISTINCT { concat_lines_of( table = columns sep = `, ` ) } | &&
                |FROM { table } ) AS init|
      columns = 1 ).
    result = rows[ 1 ][ 1 ].
  ENDMETHOD.

  METHOD row_count.
    DATA(counted) = COND string( WHEN column IS INITIAL THEN `*` ELSE |DISTINCT { zzxxmla1_cl_sql=>quote( column ) }| ).
    DATA(rows) = zzxxmla1_cl_sql=>query( sql     = |SELECT COUNT( { counted } ) FROM { zzxxmla1_cl_sql=>quote( table ) }|
                                         columns = 1 ).
    result = rows[ 1 ][ 1 ].
  ENDMETHOD.

  METHOD member_name.
    result = value.
  ENDMETHOD.

  METHOD quote_name.
    result = |[{ replace( val = name sub = `]` with = `]]` occ = 0 ) }]|.
  ENDMETHOD.

ENDCLASS.
