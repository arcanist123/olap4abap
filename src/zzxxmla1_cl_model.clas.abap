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
        fact_table      TYPE string,   " the cube's fact table
        "! the members are only the rows of the dimension table whose key is in the fact table (member_table)
        members_with_facts TYPE abap_bool,
        "! the columns' types were read from the database's catalog (key_types); else data_type tells them
        typed           TYPE abap_bool,
        "! the columns of the dimension table that are numbers in the database, which orders and compares them as such
        numeric_columns TYPE string_table,
        "! the copy of a BW hierarchy (the annotation olap4abap.bwHierarchy of ZZXXMLA1_CL_SCHEMA) at BW's version the
        "! schema was read at; initial for any other hierarchy
        bw_hierarchy    TYPE zzxxmla1_cl_bw_hierarchy_copy=>ty_hierarchy,
        "! of a BW hierarchy: the column of the dimension table that names a leaf
        bw_value_name   TYPE string,
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
        "! hierarchy order: the order keys of the keys from the first level, each after c_separator and 0 (order_key)
        order_key   TYPE string,
        children    TYPE i,
        properties  TYPE string_table,  " the values of the level's member properties, in their order
      END OF ty_member,
      ty_t_member TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_child_count,
        path  TYPE string,
        count TYPE i,
      END OF ty_child_count,
      ty_t_child_count TYPE HASHED TABLE OF ty_child_count WITH UNIQUE KEY path.
    "! The most paths constrained in one query (the reference's MaxConstraints).
    CONSTANTS c_max_constraints TYPE i VALUE 1000.
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
    "! The table the members of a hierarchy are read from: its dimension table, or, if the cube shows only the members
    "! with facts (the dimension's annotation olap4abap.membersWithFacts, our extension: a BW characteristic is shared by
    "! many providers and has many more values than one of them uses), the rows of the dimension table whose key is in
    "! the fact table, as a derived table. Fact queries join the dimension table itself: the facts restrict it anyway.
    "! The members of a BW hierarchy are the copy's, as a level hierarchy (ZZXXMLA1_CL_BW_HIERARCHY_COPY=>levels_sql):
    "! a row per member with its path's columns, the levels below it NULL, so a read of a level asks for its column
    "! not NULL (bw_level_condition).
    CLASS-METHODS member_table
      IMPORTING hierarchy     TYPE ty_hierarchy
      RETURNING VALUE(result) TYPE string.
    "! The dimension table a fact read joins on the foreign key. The level columns of a BW hierarchy are not columns of
    "! it: until the facts are read through the copy's closure (docs/next-steps.md, step 7.3), such a read fails
    "! (ZZXXMLA1_CX_BW_HIERARCHY).
    CLASS-METHODS fact_join_table
      IMPORTING hierarchy     TYPE ty_hierarchy
      RETURNING VALUE(result) TYPE string.
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
    "! The members of a level as the reference reads them (SqlMemberSource.makeChildMemberSql,
    "! makeLevelMembersSql): the distinct values of the level columns down to the level, with the names and the
    "! columns of the member properties, constrained by a condition on the columns of the dimension table, in hierarchy
    "! order (descending: in reverse order), at most limit of them (0: all) after offset.
    "! @parameter condition | SQL on the dimension table's columns (path_condition, ...); empty: none
    "! @parameter ancestors | the members of the levels above, as read with them
    CLASS-METHODS read_members
      IMPORTING hierarchy     TYPE ty_hierarchy
                level_no      TYPE i
                !condition    TYPE string OPTIONAL
                descending    TYPE abap_bool DEFAULT abap_false
                !limit        TYPE i DEFAULT 0
                !offset       TYPE i DEFAULT 0
      EXPORTING ancestors     TYPE ty_t_member
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The condition that the key columns of the levels 1 to level_no hold the keys of a path.
    CLASS-METHODS path_condition
      IMPORTING hierarchy     TYPE ty_hierarchy
                level_no      TYPE i
                !path         TYPE string
      RETURNING VALUE(result) TYPE string.
    "! The condition that the keys of the levels 1 to level_no hold one of the paths (an IN list on the first level).
    CLASS-METHODS paths_condition
      IMPORTING hierarchy     TYPE ty_hierarchy
                level_no      TYPE i
                paths         TYPE string_table
      RETURNING VALUE(result) TYPE string.
    "! The condition that the keys of the levels 1 to level_no come before (&lt;, &lt;=) or after (&gt;, &gt;=) a path in
    "! the database's order (an ORDER BY of the key columns, NULL first): the keys compared from the first level; a level
    "! with an ordinal column by its ordinal first.
    CLASS-METHODS order_condition
      IMPORTING hierarchy     TYPE ty_hierarchy
                level_no      TYPE i
                !path         TYPE string
                operator      TYPE string
      RETURNING VALUE(result) TYPE string.
    "! The condition that the name column of a level holds a name, compared case-insensitively as the reference does
    "! with olap.case.sensitive=false (ChildByNameConstraint: UPPER on both sides); a name that a numeric column cannot
    "! hold matches nothing.
    CLASS-METHODS name_condition
      IMPORTING hierarchy     TYPE ty_hierarchy
                level_no      TYPE i
                name          TYPE string
      RETURNING VALUE(result) TYPE string.
    "! The number of children of members of a level (0: the All member) by their paths (getMemberChildren counted): the
    "! distinct paths of the level below that start with each path, in one grouped query per c_max_constraints paths.
    CLASS-METHODS children_counts
      IMPORTING hierarchy     TYPE ty_hierarchy
                level_no      TYPE i
                paths         TYPE string_table
      RETURNING VALUE(result) TYPE ty_t_child_count.
    "! The members of a level built from rows of the level columns: each row holds per level the key, followed by
    "! the name if the level has a name column of its own, then the values of the level's properties; the rows are in
    "! hierarchy order. A member's properties are the ones of its first row.
    CLASS-METHODS members_of_rows
      IMPORTING hierarchy     TYPE ty_hierarchy
                rows          TYPE zzxxmla1_cl_sql=>ty_t_row
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The number of members of a level as the reference counts it (SqlMemberSource.getLevelMemberCount): the distinct
    "! values of the level's column, or of the columns of the levels down to it if its members are not unique. A level
    "! of a BW hierarchy: the members of the copy on the level's depth.
    CLASS-METHODS level_cardinality
      IMPORTING hierarchy     TYPE ty_hierarchy
                level_no      TYPE i
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
    "! A key as a part of an order key: texts that compare as the database orders the key (RolapMemberBase.compareTo,
    "! the keys as the database returns them). A number becomes P (N if negative), the length of its integer part and
    "! its digits (negative: complemented, ~ at the end), so 9 comes before 10 and -10 before -9; any other key is
    "! itself. The empty key (NULL) is empty and comes first, as NULLs do in HANA's ascending order.
    CLASS-METHODS order_key
      IMPORTING !key          TYPE string
                numeric       TYPE abap_bool
      RETURNING VALUE(result) TYPE string.
    "! Whether the database orders a level's keys as numbers: the type of its key column in the database's catalog if
    "! known (key_types), else the level's data_type.
    CLASS-METHODS is_numeric_level
      IMPORTING hierarchy     TYPE ty_hierarchy
                level_no      TYPE i
      RETURNING VALUE(result) TYPE abap_bool.
    "! Whether the database holds a column of a hierarchy's dimension table as a number: its type in the database's
    "! catalog if known (key_types), else the data_type of the schema.
    CLASS-METHODS is_numeric_column
      IMPORTING hierarchy     TYPE ty_hierarchy
                column        TYPE string
                data_type     TYPE string
      RETURNING VALUE(result) TYPE abap_bool.
    "! Reads the types of the columns of the hierarchies' dimension tables from HANA's catalog (one query for all).
    CLASS-METHODS key_types
      CHANGING hierarchies TYPE ty_t_hierarchy.

  PRIVATE SECTION.
    "! Of a BW hierarchy: the condition that a member's path reaches a level (its key column not NULL); else empty.
    CLASS-METHODS bw_level_condition
      IMPORTING hierarchy     TYPE ty_hierarchy
                level_no      TYPE i
      RETURNING VALUE(result) TYPE string.
    "! The columns of the levels: per level its key, its name if it has a name column of its own, the columns of its
    "! member properties; and the key columns to order by.
    CLASS-METHODS level_columns
      IMPORTING hierarchy TYPE ty_hierarchy
      EXPORTING columns   TYPE string_table
                order_by  TYPE string_table.
    "! The condition that a key column comes before (&lt;) or after (&gt;) a key in the database's order, NULL first.
    CLASS-METHODS key_order_condition
      IMPORTING column        TYPE string
                !key          TYPE string
                operator      TYPE string
      RETURNING VALUE(result) TYPE string.
ENDCLASS.

CLASS zzxxmla1_cl_model IMPLEMENTATION.

  METHOD hierarchy_unique_name.
    result = COND #( WHEN hier_name = dim_name THEN |[{ dim_name }]| ELSE |[{ dim_name }.{ hier_name }]| ).
  ENDMETHOD.

  METHOD hierarchies.
    DATA(schema) = zzxxmla1_cl_schema=>get( ).
    DATA(cubes) = schema->cubes( ).
    READ TABLE cubes INTO DATA(the_cube) WITH KEY cube_name = cube.
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
                        dim_type        = dim-dim_type
                        fact_table      = the_cube-fact_table
                        members_with_facts = dim-members_with_facts
                        bw_hierarchy    = hier-bw_hierarchy
                        bw_value_name   = hier-bw_value_name ) TO result.
      ENDLOOP.
    ENDLOOP.
    key_types( CHANGING hierarchies = result ).
  ENDMETHOD.

  METHOD member_table.
    IF hierarchy-bw_hierarchy IS NOT INITIAL.
      result = |( { zzxxmla1_cl_bw_hierarchy_copy=>levels_sql( hierarchy   = hierarchy-bw_hierarchy
                                                                depth       = lines( hierarchy-levels )
                                                                value_table = hierarchy-dim_table
                                                                sid_column  = hierarchy-key_column
                                                                name_column = hierarchy-bw_value_name ) } ) AS bw|.
      RETURN.
    ENDIF.
    result = zzxxmla1_cl_sql=>quote( hierarchy-dim_table ).
    IF hierarchy-members_with_facts = abap_true.
      result = |( SELECT * FROM { result } WHERE { zzxxmla1_cl_sql=>quote( hierarchy-key_column ) } IN | &&
               |( SELECT { zzxxmla1_cl_sql=>quote( hierarchy-fk_column ) } | &&
               |FROM { zzxxmla1_cl_sql=>quote( hierarchy-fact_table ) } ) ) AS mf|.
    ENDIF.
  ENDMETHOD.

  METHOD fact_join_table.
    IF hierarchy-bw_hierarchy IS NOT INITIAL.
      RAISE EXCEPTION TYPE zzxxmla1_cx_bw_hierarchy
        EXPORTING
          error_message = |The cells of the BW hierarchy { hierarchy-bw_hierarchy-name } of | &&
                          |{ hierarchy-bw_hierarchy-characteristic } ({ hierarchy-unique_name }) are not supported yet|.
    ENDIF.
    result = zzxxmla1_cl_sql=>quote( hierarchy-dim_table ).
  ENDMETHOD.

  METHOD measures.
    LOOP AT zzxxmla1_cl_schema=>get( )->measures( cube ) INTO DATA(measure).
      APPEND VALUE #( name = measure-meas_name fact_column = measure-fact_column aggregator = measure-aggregator
                      format = measure-format_string ) TO result.
    ENDLOOP.
    APPEND VALUE #( name = `Fact Count` aggregator = `count` ) TO result.
  ENDMETHOD.

  METHOD members.
    level_columns( EXPORTING hierarchy = hierarchy IMPORTING columns = DATA(columns) order_by = DATA(order_by) ).
    DATA(rows) = zzxxmla1_cl_sql=>query(
      sql     = |SELECT DISTINCT { concat_lines_of( table = columns sep = `, ` ) } | &&
                |FROM { member_table( hierarchy ) } | &&
                |ORDER BY { concat_lines_of( table = order_by sep = `, ` ) }|
      columns = lines( columns ) ).
    result = members_of_rows( hierarchy = hierarchy rows = rows ).
  ENDMETHOD.

  METHOD level_columns.
    CLEAR: columns, order_by.
    LOOP AT hierarchy-levels INTO DATA(level).
      APPEND zzxxmla1_cl_sql=>quote( level-key_column ) TO columns.
      " an ordinal column orders the members, the key the ones of the same ordinal (SqlMemberSource); it is read
      " once, also when it is the name column
      IF level-ordinal_column IS NOT INITIAL.
        IF level-ordinal_column <> level-name_column.
          APPEND zzxxmla1_cl_sql=>quote( level-ordinal_column ) TO columns.
        ENDIF.
        APPEND zzxxmla1_cl_sql=>quote( level-ordinal_column ) TO order_by.
      ENDIF.
      APPEND zzxxmla1_cl_sql=>quote( level-key_column ) TO order_by.
      IF level-name_column <> level-key_column.
        APPEND zzxxmla1_cl_sql=>quote( level-name_column ) TO columns.
      ENDIF.
      LOOP AT level-properties INTO DATA(property).
        APPEND zzxxmla1_cl_sql=>quote( property-column ) TO columns.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD read_members.
    " the hierarchy down to the level: its columns are read, members_of_rows makes the members of all of them
    DATA(down) = hierarchy.
    DELETE down-levels FROM level_no + 1.
    level_columns( EXPORTING hierarchy = down IMPORTING columns = DATA(columns) order_by = DATA(order_by) ).
    DATA(direction) = COND string( WHEN descending = abap_true THEN ` DESC` ELSE ` ASC` ).
    DATA(conditions) = VALUE string_table( ( bw_level_condition( hierarchy = hierarchy level_no = level_no ) ) ).
    IF condition IS NOT INITIAL.
      APPEND |( { condition } )| TO conditions.
    ENDIF.
    DELETE conditions WHERE table_line IS INITIAL.
    DATA(sql) = |SELECT DISTINCT { concat_lines_of( table = columns sep = `, ` ) } | &&
                |FROM { member_table( hierarchy ) }| &&
                COND #( WHEN conditions IS NOT INITIAL
                        THEN | WHERE { concat_lines_of( table = conditions sep = ` AND ` ) }| ) &&
                | ORDER BY { concat_lines_of( table = order_by sep = |{ direction }, | ) }{ direction }|.
    IF limit > 0.
      sql = |{ sql } LIMIT { limit }| && COND #( WHEN offset > 0 THEN | OFFSET { offset }| ).
    ENDIF.
    result = members_of_rows( hierarchy = down rows = zzxxmla1_cl_sql=>query( sql = sql columns = lines( columns ) ) ).
    " the members of the levels above come with the rows: the ancestors, once each
    DATA(target) = level_no.
    ancestors = VALUE #( FOR m IN result WHERE ( level_no <> target ) ( m ) ).
    SORT ancestors BY level_no ASCENDING path ASCENDING.
    DELETE ADJACENT DUPLICATES FROM ancestors COMPARING level_no path.
    DELETE result WHERE level_no <> target.
  ENDMETHOD.

  METHOD bw_level_condition.
    IF hierarchy-bw_hierarchy IS NOT INITIAL.
      result = |{ zzxxmla1_cl_sql=>quote( hierarchy-levels[ level_no ]-key_column ) } IS NOT NULL|.
    ENDIF.
  ENDMETHOD.

  METHOD path_condition.
    SPLIT path AT c_separator INTO TABLE DATA(keys).
    DATA(conditions) = VALUE string_table( ).
    LOOP AT hierarchy-levels INTO DATA(level) TO level_no.
      APPEND zzxxmla1_cl_sql=>key_condition( column = zzxxmla1_cl_sql=>quote( level-key_column )
                                             key    = VALUE #( keys[ sy-tabix ] OPTIONAL ) ) TO conditions.
    ENDLOOP.
    result = |( { concat_lines_of( table = conditions sep = ` AND ` ) } )|.
  ENDMETHOD.

  METHOD paths_condition.
    IF paths IS INITIAL.
      result = `1 = 0`.
      RETURN.
    ENDIF.
    DATA(conditions) = VALUE string_table( ).
    IF level_no = 1 OR hierarchy-levels[ level_no ]-unique_members = abap_true.
      " the first level or one of unique members: its key alone tells the member (SqlConstraintUtils.constrainLevel
      " up to a unique level); the non-empty keys in a list
      DATA(keys) = VALUE string_table( ).
      LOOP AT paths INTO DATA(path).
        DATA(key) = substring_after( val = path sub = c_separator occ = -1 ).
        IF key IS INITIAL AND path NS c_separator.
          key = path.
        ENDIF.
        APPEND key TO keys.
      ENDLOOP.
      DATA(column) = zzxxmla1_cl_sql=>quote( hierarchy-levels[ level_no ]-key_column ).
      DATA(literals) = VALUE string_table( FOR k IN keys WHERE ( table_line IS NOT INITIAL )
                                           ( zzxxmla1_cl_sql=>literal( k ) ) ).
      IF literals IS NOT INITIAL.
        APPEND |{ column } IN ( { concat_lines_of( table = literals sep = `, ` ) } )| TO conditions.
      ENDIF.
      IF line_exists( keys[ table_line = `` ] ).
        APPEND zzxxmla1_cl_sql=>key_condition( column = column key = `` ) TO conditions.
      ENDIF.
    ELSE.
      LOOP AT paths INTO path.
        APPEND path_condition( hierarchy = hierarchy level_no = level_no path = path ) TO conditions.
      ENDLOOP.
    ENDIF.
    result = |( { concat_lines_of( table = conditions sep = ` OR ` ) } )|.
  ENDMETHOD.

  METHOD order_condition.
    " the first level whose key differs decides: the keys above it equal, it before or after; <= and >= the path too
    SPLIT path AT c_separator INTO TABLE DATA(keys).
    DATA(strict) = substring( val = operator len = 1 ).
    DATA(disjuncts) = VALUE string_table( ).
    DATA(equal) = VALUE string_table( ).
    LOOP AT hierarchy-levels INTO DATA(level) TO level_no.
      DATA(key) = VALUE string( keys[ sy-tabix ] OPTIONAL ).
      DATA(column) = zzxxmla1_cl_sql=>quote( level-key_column ).
      DATA(conjuncts) = equal.
      IF level-ordinal_column IS INITIAL.
        APPEND key_order_condition( column = column key = key operator = strict ) TO conjuncts.
      ELSE.
        " ordered by the ordinal, then by the key: the path's ordinal from the table (one per key)
        DATA(ordinal) = zzxxmla1_cl_sql=>quote( level-ordinal_column ).
        DATA(of_path) = |( SELECT MAX( { ordinal } ) FROM { member_table( hierarchy ) } WHERE | &&
                        |{ concat_lines_of( table = VALUE string_table( ( LINES OF equal )
                                                                         ( zzxxmla1_cl_sql=>key_condition( column = column
                                                                                                          key    = key ) ) )
                                            sep   = ` AND ` ) } )|.
        APPEND |( { ordinal } { strict } { of_path } OR ( { ordinal } = { of_path } AND | &&
               |{ key_order_condition( column = column key = key operator = strict ) } ) )| TO conjuncts.
      ENDIF.
      APPEND |( { concat_lines_of( table = conjuncts sep = ` AND ` ) } )| TO disjuncts.
      APPEND zzxxmla1_cl_sql=>key_condition( column = column key = key ) TO equal.
    ENDLOOP.
    IF strlen( operator ) = 2.
      APPEND |( { concat_lines_of( table = equal sep = ` AND ` ) } )| TO disjuncts.
    ENDIF.
    result = |( { concat_lines_of( table = disjuncts sep = ` OR ` ) } )|.
  ENDMETHOD.

  METHOD key_order_condition.
    IF key IS INITIAL.
      " NULL (or empty) comes first: nothing before it, every other key after it
      result = COND #( WHEN operator = `<` THEN `1 = 0` ELSE |COALESCE( TO_NVARCHAR( { column } ), '' ) <> ''| ).
    ELSEIF operator = `<`.
      result = |( { column } < { zzxxmla1_cl_sql=>literal( key ) } OR { column } IS NULL )|.
    ELSE.
      result = |{ column } > { zzxxmla1_cl_sql=>literal( key ) }|.
    ENDIF.
  ENDMETHOD.

  METHOD name_condition.
    DATA(level) = hierarchy-levels[ level_no ].
    DATA(column) = zzxxmla1_cl_sql=>quote( level-name_column ).
    IF name IS INITIAL.
      result = zzxxmla1_cl_sql=>key_condition( column = column key = name ).
    ELSEIF is_numeric_column( hierarchy = hierarchy column = level-name_column data_type = level-data_type ) = abap_true.
      " a number compared as one; any other name is no number's text
      result = COND #( WHEN matches( val = name regex = `-?\d+(\.\d+)?` ) THEN |{ column } = { name }| ELSE `1 = 0` ).
    ELSEIF find( val = name regex = `[[:alpha:]]` ) < 0.
      " no letters: UPPER changes nothing, so the column holds the name itself (a lookup, not a scan)
      result = |{ column } = { zzxxmla1_cl_sql=>literal( name ) }|.
    ELSE.
      result = |UPPER( { column } ) = UPPER( { zzxxmla1_cl_sql=>literal( name ) } )|.
    ENDIF.
  ENDMETHOD.

  METHOD children_counts.
    DATA(table) = member_table( hierarchy ).
    IF level_no = 0.
      " the All member: the members of the first level
      DATA(first) = zzxxmla1_cl_sql=>quote( hierarchy-levels[ 1 ]-key_column ).
      DATA(rows) = zzxxmla1_cl_sql=>query(
        sql     = |SELECT COUNT( * ) FROM ( SELECT DISTINCT { first } FROM { table } ) AS c|
        columns = 1 ).
      INSERT VALUE #( path = `` count = rows[ 1 ][ 1 ] ) INTO TABLE result.
      RETURN.
    ENDIF.
    IF level_no >= lines( hierarchy-levels ).
      RETURN.
    ENDIF.
    DATA(parents) = VALUE string_table( ).
    DATA(children) = VALUE string_table( ).
    LOOP AT hierarchy-levels INTO DATA(level) TO level_no + 1.
      DATA(column) = zzxxmla1_cl_sql=>quote( level-key_column ).
      APPEND column TO children.
      IF sy-tabix <= level_no.
        APPEND column TO parents.
      ENDIF.
    ENDLOOP.
    DATA(chunk) = VALUE string_table( ).
    LOOP AT paths INTO DATA(path).
      DATA(last) = xsdbool( sy-tabix = lines( paths ) ).
      APPEND path TO chunk.
      IF lines( chunk ) < c_max_constraints AND last = abap_false.
        CONTINUE.
      ENDIF.
      rows = zzxxmla1_cl_sql=>query(
        sql     = |SELECT { concat_lines_of( table = parents sep = `, ` ) }, COUNT( * ) FROM ( | &&
                  |SELECT DISTINCT { concat_lines_of( table = children sep = `, ` ) } FROM { table } | &&
                  |WHERE { paths_condition( hierarchy = hierarchy level_no = level_no paths = chunk ) }| &&
                  |{ COND #( WHEN hierarchy-bw_hierarchy IS NOT INITIAL
                             THEN | AND { bw_level_condition( hierarchy = hierarchy level_no = level_no + 1 ) }| ) }| &&
                  | ) AS c | &&
                  |GROUP BY { concat_lines_of( table = parents sep = `, ` ) }|
        columns = level_no + 1 ).
      LOOP AT rows INTO DATA(row).
        DATA(count) = row[ level_no + 1 ].
        DELETE row INDEX level_no + 1.
        INSERT VALUE #( path = concat_lines_of( table = row sep = c_separator ) count = count ) INTO TABLE result.
      ENDLOOP.
      CLEAR chunk.
    ENDLOOP.
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
      DATA(order) = VALUE string( ).
      DATA(parent) = VALUE string( ).
      DATA(parent_unique) = hierarchy-unique_name.
      LOOP AT hierarchy-levels INTO DATA(level).
        DATA(level_no) = sy-tabix.
        column = column + 1.
        DATA(key) = row[ column ].
        IF key IS INITIAL AND hierarchy-bw_hierarchy IS NOT INITIAL.
          " a member of a BW hierarchy above the deepest level: the levels below it are NULL
          EXIT.
        ENDIF.
        DATA(ordinal) = VALUE string( ).
        IF level-ordinal_column IS NOT INITIAL AND level-ordinal_column <> level-name_column.
          column = column + 1.
          ordinal = row[ column ].
        ENDIF.
        DATA(name) = member_name( value = key data_type = level-data_type ).
        IF level-name_column <> level-key_column.
          column = column + 1.
          name = row[ column ].
        ENDIF.
        " the order key of a level with an ordinal column: the ordinal's, then the key's (RolapMemberBase.compareTo)
        IF level-ordinal_column IS NOT INITIAL.
          IF level-ordinal_column = level-name_column.
            ordinal = name.
          ENDIF.
          order = order && c_separator && `0`
                  && order_key( key     = ordinal
                                numeric = is_numeric_column( hierarchy = hierarchy column = level-ordinal_column
                                                             data_type = `String` ) ).
        ENDIF.
        order = order && c_separator && `0`
                && order_key( key = key numeric = is_numeric_level( hierarchy = hierarchy level_no = level_no ) ).
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
                          parent = parent order_key = order properties = properties ) TO result.
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
    IF hierarchy-bw_hierarchy IS NOT INITIAL.
      result = zzxxmla1_cl_bw_hierarchy_copy=>level_cardinality( hierarchy = hierarchy-bw_hierarchy level = level_no ).
      RETURN.
    ENDIF.
    DATA(level) = hierarchy-levels[ level_no ].
    DATA(table) = member_table( hierarchy ).
    IF level-unique_members = abap_true OR level_no = 1.
      DATA(counted) = zzxxmla1_cl_sql=>query(
        sql     = |SELECT COUNT( DISTINCT { zzxxmla1_cl_sql=>quote( level-key_column ) } ) FROM { table }|
        columns = 1 ).
      result = counted[ 1 ][ 1 ].
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

  METHOD member_name.
    result = value.
  ENDMETHOD.

  METHOD quote_name.
    result = |[{ replace( val = name sub = `]` with = `]]` occ = 0 ) }]|.
  ENDMETHOD.

  METHOD order_key.
    result = key.
    IF numeric = abap_false OR key IS INITIAL OR NOT matches( val = key regex = `[+-]?\d*(\.\d*)?` ).
      RETURN.
    ENDIF.
    DATA(negative) = xsdbool( key(1) = `-` ).
    DATA(digits) = COND string( WHEN key(1) = `-` OR key(1) = `+` THEN substring( val = key off = 1 ) ELSE key ).
    SPLIT digits AT `.` INTO DATA(integer) DATA(fraction).
    integer = shift_left( val = integer sub = `0` ).
    fraction = shift_right( val = fraction sub = `0` ).
    DATA(length) = strlen( integer ).
    IF negative = abap_false OR ( integer IS INITIAL AND fraction IS INITIAL ).
      result = |P{ length WIDTH = 2 ALIGN = RIGHT PAD = `0` }{ integer }{ fraction }|.
    ELSE.
      result = |N{ 99 - length WIDTH = 2 ALIGN = RIGHT PAD = `0` }| &&
               |{ translate( val = integer && fraction from = `0123456789` to = `9876543210` ) }~|.
    ENDIF.
  ENDMETHOD.

  METHOD is_numeric_level.
    result = is_numeric_column( hierarchy = hierarchy column = hierarchy-levels[ level_no ]-key_column
                                data_type = hierarchy-levels[ level_no ]-data_type ).
  ENDMETHOD.

  METHOD is_numeric_column.
    IF hierarchy-typed = abap_true.
      result = xsdbool( line_exists( hierarchy-numeric_columns[ table_line = column ] ) ).
    ELSE.
      result = xsdbool( data_type = `Numeric` ).
    ENDIF.
  ENDMETHOD.

  METHOD key_types.
    TYPES:
      BEGIN OF ty_column,
        table     TYPE string,
        column    TYPE string,
        data_type TYPE string,
      END OF ty_column.
    DATA columns TYPE HASHED TABLE OF ty_column WITH UNIQUE KEY table column.
    DATA tables TYPE string_table.
    LOOP AT hierarchies INTO DATA(hierarchy).
      IF NOT line_exists( tables[ table_line = hierarchy-dim_table ] ).
        APPEND hierarchy-dim_table TO tables.
      ENDIF.
    ENDLOOP.
    IF tables IS INITIAL.
      RETURN.
    ENDIF.
    DATA(names) = concat_lines_of( table = VALUE string_table( FOR t IN tables ( zzxxmla1_cl_sql=>literal( t ) ) )
                                   sep   = `, ` ).
    DATA(sql) = |SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE_NAME FROM SYS.TABLE_COLUMNS | &&
                |WHERE SCHEMA_NAME = CURRENT_SCHEMA AND TABLE_NAME IN ( { names } ) UNION ALL | &&
                |SELECT VIEW_NAME, COLUMN_NAME, DATA_TYPE_NAME FROM SYS.VIEW_COLUMNS | &&
                |WHERE SCHEMA_NAME = CURRENT_SCHEMA AND VIEW_NAME IN ( { names } )|.
    LOOP AT zzxxmla1_cl_sql=>query( sql = sql columns = 3 ) INTO DATA(row).
      INSERT VALUE #( table = row[ 1 ] column = row[ 2 ] data_type = row[ 3 ] ) INTO TABLE columns.
    ENDLOOP.
    LOOP AT hierarchies ASSIGNING FIELD-SYMBOL(<hierarchy>).
      IF <hierarchy>-bw_hierarchy IS NOT INITIAL.
        " the copy's levels: SIDs and positions are numbers
        <hierarchy>-typed = abap_true.
        LOOP AT <hierarchy>-levels INTO DATA(bw_level).
          APPEND bw_level-key_column TO <hierarchy>-numeric_columns.
          APPEND bw_level-ordinal_column TO <hierarchy>-numeric_columns.
        ENDLOOP.
        CONTINUE.
      ENDIF.
      " a key column the catalog does not know (an expression, another schema): the schema's types
      <hierarchy>-typed = abap_true.
      LOOP AT <hierarchy>-levels INTO DATA(level).
        IF NOT line_exists( columns[ table = <hierarchy>-dim_table column = level-key_column ] ).
          <hierarchy>-typed = abap_false.
        ENDIF.
      ENDLOOP.
      IF <hierarchy>-typed = abap_false.
        CONTINUE.
      ENDIF.
      LOOP AT columns INTO DATA(column) WHERE table = <hierarchy>-dim_table.
        CASE column-data_type.
          WHEN `INTEGER` OR `SMALLINT` OR `TINYINT` OR `BIGINT` OR `DECIMAL` OR `SMALLDECIMAL` OR `DOUBLE` OR `REAL`
            OR `FLOAT`.
            APPEND column-column TO <hierarchy>-numeric_columns.
        ENDCASE.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
