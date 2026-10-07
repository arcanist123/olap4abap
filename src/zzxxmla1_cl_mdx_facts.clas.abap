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
"! Reads the cell values of a cube from its fact table with native SQL. A cell is the measure aggregated over the
"! facts of the members it is restricted to (a filter is a hierarchy and the keys of a member and its ancestors, its
"! path; a hierarchy without filter is its All member). The facts are grouped by the level columns of the filtered
"! hierarchies down to the filtered levels, once per combination of hierarchies and levels, and the answers are kept: a
"! cell is then a lookup. The slicer is part of the filters of a cell. The subcube of a subselect restricts every read
"! (set_subcube).
CLASS zzxxmla1_cl_mdx_facts DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_filter,
        hierarchy TYPE i,        " position in the hierarchies of the cube
        level     TYPE i,        " the level of the member, from 1
        path      TYPE string,   " the keys of the levels 1 to level (ZZXXMLA1_CL_MODEL, ty_member-path)
        any       TYPE abap_bool,  " non_empty_paths: any member of the level, whose path is returned
      END OF ty_filter,
      ty_t_filter TYPE STANDARD TABLE OF ty_filter WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_value,
        empty  TYPE abap_bool,   " no fact: the reference's empty cell
        amount TYPE decfloat34,
      END OF ty_value.
    "! the paths of the filters marked any, in their order
    TYPES ty_t_paths TYPE STANDARD TABLE OF string_table WITH EMPTY KEY.
    "! A node of the subcube predicate (the reference server's StarPredicate of Query.getSubcubePredicates): AND, OR or NOT of its
    "! children (indexes in the predicate table), MEMBER (the facts of a member: the key columns of its levels equal
    "! its path; the All member any fact) or FALSE.
    TYPES ty_t_index TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_predicate,
        kind     TYPE string,
        children TYPE ty_t_index,
        member   TYPE ty_filter,
      END OF ty_predicate,
      "! the nodes of a predicate, the root first; empty: no restriction
      ty_t_predicate TYPE STANDARD TABLE OF ty_predicate WITH EMPTY KEY.
    CONSTANTS:
      BEGIN OF c_predicate,
        and    TYPE string VALUE `AND`,
        or     TYPE string VALUE `OR`,
        not    TYPE string VALUE `NOT`,
        member TYPE string VALUE `MEMBER`,
        false  TYPE string VALUE `FALSE`,
      END OF c_predicate.

    METHODS constructor
      IMPORTING cube        TYPE zzxxmla1_cl_schema=>ty_cube
                hierarchies TYPE zzxxmla1_cl_model=>ty_t_hierarchy
                measures    TYPE zzxxmla1_cl_model=>ty_t_measure.
    "! @parameter measure | position in the measures of the cube
    METHODS value
      IMPORTING filters       TYPE ty_t_filter
                measure       TYPE i
      RETURNING VALUE(result) TYPE ty_value.
    "! The native crossjoin's tuple reader (SqlTupleReader with a SqlContextConstraint): the combinations of members of
    "! the levels of the filters marked any that have facts with the other filters, as their paths. The facts are
    "! grouped as for value, so this is one query, or none if value has grouped them so already.
    METHODS non_empty_paths
      IMPORTING filters       TYPE ty_t_filter
      RETURNING VALUE(result) TYPE ty_t_paths.
    "! The subcube of the query (a subselect): only the facts it admits are read, by value and non_empty_paths alike,
    "! as the reference server adds it to every cell request and native set (RolapEvaluator.getSubcubePredicate).
    METHODS set_subcube
      IMPORTING predicate TYPE ty_t_predicate.

  PRIVATE SECTION.
    TYPES ty_t_amount TYPE STANDARD TABLE OF decfloat34 WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_group,
        key   TYPE string,
        sums  TYPE ty_t_amount,
        count TYPE i,
      END OF ty_group,
      ty_t_group TYPE HASHED TABLE OF ty_group WITH UNIQUE KEY key.
    TYPES:
      BEGIN OF ty_cache,
        pattern TYPE string,
        groups  TYPE ty_t_group,
      END OF ty_cache.

    DATA cube        TYPE zzxxmla1_cl_schema=>ty_cube.
    DATA hierarchies TYPE zzxxmla1_cl_model=>ty_t_hierarchy.
    DATA measures    TYPE zzxxmla1_cl_model=>ty_t_measure.
    DATA cache       TYPE HASHED TABLE OF ty_cache WITH UNIQUE KEY pattern.
    DATA subcube     TYPE ty_t_predicate.
    "! The SQL condition of a node of the subcube predicate; the hierarchies of its members are joined as s<id>.
    METHODS predicate_sql
      IMPORTING index         TYPE i
      CHANGING  joined        TYPE ty_t_index
      RETURNING VALUE(result) TYPE string.

    "! Groups the facts by the level columns of the filters' hierarchies down to their levels and stores the sums of
    "! all measures.
    METHODS load
      IMPORTING filters       TYPE ty_t_filter
      RETURNING VALUE(result) TYPE ty_t_group.
ENDCLASS.

CLASS zzxxmla1_cl_mdx_facts IMPLEMENTATION.

  METHOD constructor.
    me->cube = cube.
    me->hierarchies = hierarchies.
    me->measures = measures.
  ENDMETHOD.

  METHOD value.
    " the filters by hierarchy: as they come if they are in that order already (the evaluator's are)
    DATA sorted TYPE ty_t_filter.
    FIELD-SYMBOLS <sorted> TYPE ty_t_filter.
    ASSIGN filters TO <sorted>.
    DATA(previous) = -1.
    LOOP AT filters ASSIGNING FIELD-SYMBOL(<filter>).
      IF <filter>-hierarchy < previous.
        sorted = filters.
        SORT sorted BY hierarchy ASCENDING.
        ASSIGN sorted TO <sorted>.
        EXIT.
      ENDIF.
      previous = <filter>-hierarchy.
    ENDLOOP.
    DATA(pattern) = VALUE string( ).
    DATA(key) = VALUE string( ).
    LOOP AT <sorted> ASSIGNING <filter>.
      pattern = pattern && <filter>-hierarchy && `:` && <filter>-level && `,`.
      key = key && <filter>-path && zzxxmla1_cl_model=>c_separator.
    ENDLOOP.

    IF NOT line_exists( cache[ pattern = pattern ] ).
      INSERT VALUE #( pattern = pattern groups = load( <sorted> ) ) INTO TABLE cache.
    ENDIF.
    ASSIGN cache[ pattern = pattern ] TO FIELD-SYMBOL(<cache>).
    ASSIGN <cache>-groups[ key = key ] TO FIELD-SYMBOL(<group>).
    IF sy-subrc <> 0 OR <group>-count = 0.
      result-empty = abap_true.
      RETURN.
    ENDIF.
    IF measures[ measure ]-aggregator = `count`.
      result-amount = <group>-count.
    ELSE.
      result-amount = <group>-sums[ measure ].
    ENDIF.
  ENDMETHOD.

  METHOD set_subcube.
    subcube = predicate.
    " the facts read so far were read without it
    CLEAR cache.
  ENDMETHOD.

  METHOD predicate_sql.
    DATA(node) = subcube[ index ].
    CASE node-kind.
      WHEN c_predicate-member.
        IF node-member-level = 0.
          result = `1 = 1`.
          RETURN.
        ENDIF.
        DATA(id) = node-member-hierarchy.
        IF NOT line_exists( joined[ table_line = id ] ).
          APPEND id TO joined.
        ENDIF.
        SPLIT node-member-path AT zzxxmla1_cl_model=>c_separator INTO TABLE DATA(keys).
        DATA(conditions) = VALUE string_table( ).
        LOOP AT hierarchies[ id ]-levels INTO DATA(level) TO node-member-level.
          DATA(key) = COND string( WHEN sy-tabix <= lines( keys ) THEN keys[ sy-tabix ] ).
          APPEND zzxxmla1_cl_sql=>key_condition( column = |s{ id }.{ zzxxmla1_cl_sql=>quote( level-key_column ) }|
                                                 key    = key ) TO conditions.
        ENDLOOP.
        result = |( { concat_lines_of( table = conditions sep = ` AND ` ) } )|.
      WHEN c_predicate-and OR c_predicate-or.
        DATA(parts) = VALUE string_table( ).
        LOOP AT node-children INTO DATA(child).
          APPEND predicate_sql( EXPORTING index = child CHANGING joined = joined ) TO parts.
        ENDLOOP.
        IF parts IS INITIAL.
          result = COND #( WHEN node-kind = c_predicate-and THEN `1 = 1` ELSE `1 = 0` ).
        ELSE.
          result = |( { concat_lines_of( table = parts sep = | { node-kind } | ) } )|.
        ENDIF.
      WHEN c_predicate-not.
        result = |NOT { predicate_sql( EXPORTING index = node-children[ 1 ] CHANGING joined = joined ) }|.
      WHEN OTHERS.
        result = `1 = 0`.
    ENDCASE.
  ENDMETHOD.

  METHOD non_empty_paths.
    DATA(sorted) = filters.
    SORT sorted BY hierarchy ASCENDING.
    DATA(pattern) = VALUE string( ).
    LOOP AT sorted INTO DATA(filter).
      pattern = pattern && filter-hierarchy && `:` && filter-level && `,`.
    ENDLOOP.
    IF NOT line_exists( cache[ pattern = pattern ] ).
      INSERT VALUE #( pattern = pattern groups = load( sorted ) ) INTO TABLE cache.
    ENDIF.
    ASSIGN cache[ pattern = pattern ] TO FIELD-SYMBOL(<cache>).
    DATA tokens TYPE string_table.
    DATA paths TYPE HASHED TABLE OF ty_filter WITH UNIQUE KEY hierarchy.
    LOOP AT <cache>-groups ASSIGNING FIELD-SYMBOL(<group>) WHERE count > 0.
      " the key: per filter its path (as many keys as its level), as load builds it
      SPLIT <group>-key AT zzxxmla1_cl_model=>c_separator INTO TABLE tokens.
      CLEAR paths.
      DATA(position) = 0.
      DATA(matches) = abap_true.
      LOOP AT sorted INTO filter.
        DATA(path) = ``.
        DO filter-level TIMES.
          position = position + 1.
          DATA(token) = COND string( WHEN position <= lines( tokens ) THEN tokens[ position ] ).
          path = COND #( WHEN sy-index = 1 THEN token ELSE path && zzxxmla1_cl_model=>c_separator && token ).
        ENDDO.
        IF filter-any = abap_false AND path <> filter-path.
          matches = abap_false.
          EXIT.
        ENDIF.
        INSERT VALUE #( hierarchy = filter-hierarchy path = path ) INTO TABLE paths.
      ENDLOOP.
      IF matches = abap_true.
        APPEND VALUE #( FOR f IN filters WHERE ( any = abap_true ) ( paths[ hierarchy = f-hierarchy ]-path ) ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD load.
    " one join per hierarchy that is grouped by: the fact table with the dimension table on the foreign key
    DATA(source) = |{ zzxxmla1_cl_sql=>quote( cube-fact_table ) } f|.
    LOOP AT filters INTO DATA(filter).
      DATA(id) = filter-hierarchy.
      DATA(hierarchy) = hierarchies[ id ].
      source = source && | INNER JOIN { zzxxmla1_cl_sql=>quote( hierarchy-dim_table ) } d{ id }| &&
               | ON d{ id }.{ zzxxmla1_cl_sql=>quote( hierarchy-key_column ) }| &&
               | = f.{ zzxxmla1_cl_sql=>quote( hierarchy-fk_column ) }|.
    ENDLOOP.

    " the level columns of the hierarchies down to the filtered levels, the sums of the measures on a fact column, the
    " fact count
    DATA(group_by) = VALUE string_table( ).
    LOOP AT filters INTO filter.
      LOOP AT hierarchies[ filter-hierarchy ]-levels INTO DATA(level) TO filter-level.
        APPEND |d{ filter-hierarchy }.{ zzxxmla1_cl_sql=>quote( level-key_column ) }| TO group_by.
      ENDLOOP.
    ENDLOOP.
    DATA(select_list) = group_by.
    LOOP AT measures INTO DATA(measure) WHERE aggregator <> `count`.
      APPEND |SUM( f.{ zzxxmla1_cl_sql=>quote( measure-fact_column ) } )| TO select_list.
    ENDLOOP.
    APPEND `COUNT( * )` TO select_list.
    " the subcube: its condition, with the hierarchies of its members joined once more
    DATA(where) = VALUE string( ).
    IF subcube IS NOT INITIAL.
      DATA joined TYPE ty_t_index.
      DATA(condition) = predicate_sql( EXPORTING index = 1 CHANGING joined = joined ).
      LOOP AT joined INTO DATA(joined_id).
        source = source && | INNER JOIN { zzxxmla1_cl_sql=>quote( hierarchies[ joined_id ]-dim_table ) } s{ joined_id }| &&
                 | ON s{ joined_id }.{ zzxxmla1_cl_sql=>quote( hierarchies[ joined_id ]-key_column ) }| &&
                 | = f.{ zzxxmla1_cl_sql=>quote( hierarchies[ joined_id ]-fk_column ) }|.
      ENDLOOP.
      where = | WHERE { condition }|.
    ENDIF.
    DATA(sql) = |SELECT { concat_lines_of( table = select_list sep = `, ` ) } FROM { source }{ where }| &&
                COND string( WHEN group_by IS NOT INITIAL
                             THEN | GROUP BY { concat_lines_of( table = group_by sep = `, ` ) }| ).

    LOOP AT zzxxmla1_cl_sql=>query( sql = sql columns = lines( select_list ) ) INTO DATA(row).
      " the key: per filter its path, as value builds it
      DATA(group) = VALUE ty_group( ).
      DATA(column) = 0.
      LOOP AT filters INTO filter.
        DO filter-level TIMES.
          column = column + 1.
          group-key = group-key && row[ column ] && COND string( WHEN sy-index < filter-level
                                                                 THEN zzxxmla1_cl_model=>c_separator ).
        ENDDO.
        group-key = group-key && zzxxmla1_cl_model=>c_separator.
      ENDLOOP.
      LOOP AT measures INTO measure.
        IF measure-aggregator = `count`.
          APPEND 0 TO group-sums.
        ELSE.
          column = column + 1.
          DATA(sum) = row[ column ].
          APPEND COND decfloat34( WHEN sum IS INITIAL THEN 0 ELSE sum ) TO group-sums.
        ENDIF.
      ENDLOOP.
      group-count = row[ lines( select_list ) ].
      INSERT group INTO TABLE result.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
