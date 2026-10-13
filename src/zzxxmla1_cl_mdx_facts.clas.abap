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
"! hierarchies down to the filtered levels (a pattern of hierarchies and levels, the reference's bit key of constrained
"! columns), constrained to the keys of the cells asked for (CellRequest, a Segment), and the answers are kept: a cell
"! is then a lookup. While batching (FastBatchingCellReader) a cell not read yet is recorded and is 0 for this pass; the
"! engine reads the recorded cells with one query per pattern (load_aggregations) and evaluates again. The slicer is
"! part of the filters of a cell. The subcube of a subselect restricts every read (set_subcube). A drill-through reads
"! the fact rows of a cell themselves (drill_through).
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
    "! its path; the All member any fact), VALUE (a column of a hierarchy's table equal to a value, as text if quoted, or NULL,
    "! ValueColumnPredicate), TRUE or FALSE.
    TYPES ty_t_index TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_value_column,
        hierarchy TYPE i,
        column    TYPE string,
        value     TYPE string,
        is_null   TYPE abap_bool,   " the column IS NULL
        quoted    TYPE abap_bool,   " the value is compared as a string literal, else as a number
      END OF ty_value_column.
    TYPES:
      BEGIN OF ty_predicate,
        kind     TYPE string,
        children TYPE ty_t_index,
        member   TYPE ty_filter,
        column   TYPE ty_value_column,
      END OF ty_predicate,
      "! the nodes of a predicate, the root first; empty: no restriction
      ty_t_predicate TYPE STANDARD TABLE OF ty_predicate WITH EMPTY KEY.
    CONSTANTS:
      BEGIN OF c_predicate,
        and    TYPE string VALUE `AND`,
        or     TYPE string VALUE `OR`,
        not    TYPE string VALUE `NOT`,
        member TYPE string VALUE `MEMBER`,
        value  TYPE string VALUE `VALUE`,
        true   TYPE string VALUE `TRUE`,
        false  TYPE string VALUE `FALSE`,
      END OF c_predicate.
    TYPES:
      "! An item of the RETURN clause of a drill-through: a level of a hierarchy, a column of the table of a hierarchy's
      "! dimension (a DrillThroughAttribute with a sourceAttribute; level 0), or a measure (its position in the
      "! measures; 0 for a level or a column).
      BEGIN OF ty_drill_item,
        hierarchy TYPE i,
        level     TYPE i,
        measure   TYPE i,
        column    TYPE string,
        name      TYPE string,   " of the column: the name of its star column if it has none yet
      END OF ty_drill_item,
      ty_t_drill_item TYPE STANDARD TABLE OF ty_drill_item WITH EMPTY KEY.
    TYPES:
      "! A column of a drill-through answer: its name (the alias of DrillThroughQuerySpec) and the XML schema type of its
      "! database type (XmlaHandler.sqlToXsdType)
      BEGIN OF ty_drill_column,
        name     TYPE string,
        xsd_type TYPE string,
      END OF ty_drill_column,
      ty_t_drill_column TYPE STANDARD TABLE OF ty_drill_column WITH EMPTY KEY.
    TYPES:
      "! The answer of a drill-through: its columns and the values of its rows, a value per column; a number as the
      "! reference writes it (TabularRowSet.unparse). Per row which of its values are NULL: a character per column, 1
      "! for NULL (the reference leaves out their elements; the SQL reads them as empty strings).
      BEGIN OF ty_drill_through,
        columns TYPE ty_t_drill_column,
        rows    TYPE zzxxmla1_cl_sql=>ty_t_row,
        nulls   TYPE string_table,
      END OF ty_drill_through.

    "! MaxConstraints: the most keys of a column in one IN list. A column of a batch with more keys is not constrained
    "! (Aggregation.optimizePredicates).
    CLASS-DATA max_constraints TYPE i VALUE 1000.

    METHODS constructor
      IMPORTING cube        TYPE zzxxmla1_cl_schema=>ty_cube
                hierarchies TYPE zzxxmla1_cl_model=>ty_t_hierarchy
                measures    TYPE zzxxmla1_cl_model=>ty_t_measure.
    "! The cell of the filters (CellReader.get). A cell that is not read yet is read with its keys as the constraint,
    "! or, while batching, recorded for load_aggregations and its value 0 (RolapUtil.valueNotReadyException).
    "! @parameter measure | position in the measures of the cube
    METHODS value
      IMPORTING filters       TYPE ty_t_filter
                measure       TYPE i
      RETURNING VALUE(result) TYPE ty_value.
    "! Batching on (the evaluation passes of a query) or off (each missing cell is read at once).
    METHODS set_batching
      IMPORTING batching TYPE abap_bool.
    "! A cell was missed since the last load_aggregations (FastBatchingCellReader.isDirty).
    METHODS is_dirty
      RETURNING VALUE(result) TYPE abap_bool.
    METHODS set_dirty.
    "! The number of cells missed so far: a cell whose evaluation missed none is final.
    METHODS get_miss_count
      RETURNING VALUE(result) TYPE i.
    "! FastBatchingCellReader.loadAggregations: if a cell was missed, the recorded cells of each pattern are read with
    "! one query (Batch), every level column constrained to the keys of the cells asked for (unless they are more than
    "! max_constraints); true if so: the pass is to be evaluated again.
    METHODS load_aggregations
      RETURNING VALUE(result) TYPE abap_bool.
    "! The native crossjoin's tuple reader (SqlTupleReader with a SqlContextConstraint): the combinations of members of
    "! the levels of the filters marked any that have facts with the other filters, as their paths. The facts are
    "! grouped as for value, so this is one query, or none if value has grouped them so already.
    METHODS non_empty_paths
      IMPORTING filters       TYPE ty_t_filter
      RETURNING VALUE(result) TYPE ty_t_paths.
    TYPES:
      "! An operand of a native TopCount (a CrossJoinArg of TopCountConstraint): the members of a level of a hierarchy
      "! (from 1), the ones below an ancestor if it has one (its level, from 1, and its path; level 0: none).
      BEGIN OF ty_top_operand,
        hierarchy      TYPE i,
        level          TYPE i,
        ancestor_level TYPE i,
        ancestor_path  TYPE string,
      END OF ty_top_operand,
      ty_t_top_operand TYPE STANDARD TABLE OF ty_top_operand WITH EMPTY KEY,
      ty_t_count       TYPE STANDARD TABLE OF int8 WITH EMPTY KEY.
    "! The number of members of each operand, in their order (one query).
    METHODS operand_counts
      IMPORTING operands      TYPE ty_t_top_operand
      RETURNING VALUE(result) TYPE ty_t_count.
    "! RolapNativeTopCount: TopCount / BottomCount of the crossjoin of the operands by a stored measure, in the database.
    "! The crossjoin of the operands' members (each the distinct level columns of its dimension table) is joined to
    "! the facts grouped by these columns with the filters (the other hierarchies' members) and the subcube, ordered
    "! by the measure, then by the members in the order of the crossjoin (the stable sort keeps the set's order), and
    "! the first count rows are the answer, as the paths of each row's members. With empty: a left join, the tuples
    "! without facts last for TopCount, first for BottomCount (the empty value is the smallest, Sorter's comparators);
    "! else only the tuples with facts with the tuple filters (an inner join, the native crossjoin's tuples under a
    "! non-empty evaluator, whose context leaves out the default members), their value with the filters.
    "! Each statement is answered once per request (the passes of a phase evaluate the set again).
    "! @parameter measure | position in the measures
    "! @parameter top | TopCount (descending), else BottomCount
    METHODS top_count
      IMPORTING operands      TYPE ty_t_top_operand
                filters       TYPE ty_t_filter
                measure       TYPE i
                count         TYPE i
                top           TYPE abap_bool
                with_empty    TYPE abap_bool
                tuple_filters TYPE ty_t_filter OPTIONAL
      RETURNING VALUE(result) TYPE ty_t_paths.
    TYPES:
      "! An item of the ORDER BY of ordered_paths: the key column of a level of an operand (its position and the
      "! level, from 1), or a stored measure (its position in the measures; operand 0). A key compares as the reference
      "! compares a member's key (RolapMemberBase.compareTo): a number as a number, a string ignoring case first
      "! (Util.caseSensitiveCompareName). NULL (a tuple without facts) first ascending, last descending.
      BEGIN OF ty_order_item,
        operand    TYPE i,
        level      TYPE i,
        measure    TYPE i,
        descending TYPE abap_bool,
      END OF ty_order_item,
      ty_t_order_item TYPE STANDARD TABLE OF ty_order_item WITH EMPTY KEY.
    "! The crossjoin of the operands ordered in the database (top_count, and Order natively): the members' crossjoin
    "! joined to the facts as top_count joins them, the values of the measures of the items with the filters, ordered
    "! by the items, then by the members in the order of the crossjoin (the stable sort keeps the set's order); the
    "! paths of each row's members, the first limit rows. Each statement is answered once per request.
    "! @parameter limit | the most rows; 0: all
    METHODS ordered_paths
      IMPORTING operands      TYPE ty_t_top_operand
                filters       TYPE ty_t_filter
                items         TYPE ty_t_order_item
                limit         TYPE i DEFAULT 0
                with_empty    TYPE abap_bool
                tuple_filters TYPE ty_t_filter OPTIONAL
      RETURNING VALUE(result) TYPE ty_t_paths.
    "! The subcube of the query (a subselect): only the facts it admits are read, by value and non_empty_paths alike,
    "! as the reference server adds it to every cell request and native set (RolapEvaluator.getSubcubePredicate).
    METHODS set_subcube
      IMPORTING predicate TYPE ty_t_predicate.
    "! The fact rows of a cell (RolapCell.drillThroughInternal with an extended context): a request
    "! (RolapAggregationManager.makeDrillThroughRequest) of the key columns of every level of the cell's hierarchies,
    "! the levels of each member and its ancestors up to a unique level constrained to the member's keys, read as
    "! DrillThroughQuerySpec reads it: the columns in the order of the star, then the measure, ordered by the columns.
    "! A column that two members constrain to different keys is not constrained (CellRequest.addConstrainedColumn).
    "! @parameter members | the member of each hierarchy of the cell, in the order of the hierarchies (level 0: the
    "!   All member, which constrains nothing)
    "! @parameter measure | the stored measure of the cell, its position in the measures
    "! @parameter slicer | the positions of a compound slicer (an OR of ANDs of members), restricting the facts as the
    "!   subcube does; empty: none (RolapCell.buildDrillthroughSlicerPredicate)
    "! @parameter items | the RETURN clause or the cube's default drill-through action: only these columns and
    "!   measures, in this order; empty: all columns and the measure
    "! @parameter max_rows | MAXROWS, the SQL row limit; 0: none
    "! @parameter first_row | FIRSTROWSET: the number of rows skipped
    METHODS drill_through
      IMPORTING members       TYPE ty_t_filter
                measure       TYPE i
                slicer        TYPE ty_t_predicate OPTIONAL
                items         TYPE ty_t_drill_item OPTIONAL
                max_rows      TYPE i DEFAULT 0
                first_row     TYPE i DEFAULT 0
      RETURNING VALUE(result) TYPE ty_drill_through.

  PRIVATE SECTION.
    TYPES:
      "! A column of the star (RolapStar.Column): a column of a dimension's table, named by the first level that uses
      "! it (RolapStar.Table.makeColumnForLevelExpr). Its position is its bit position: the order of the levels of the
      "! hierarchies of the cube, a name column before its level's key column.
      BEGIN OF ty_star_column,
        dimension TYPE string,   " the cube's dimension, whose table holds the column
        hierarchy TYPE i,        " the first hierarchy of the dimension: its table is joined as d and its position
        column    TYPE string,
        name      TYPE string,
      END OF ty_star_column,
      ty_t_star_column TYPE STANDARD TABLE OF ty_star_column WITH EMPTY KEY.
    TYPES:
      "! The star columns of a level: its key column and the column of its names (0: the level has none).
      BEGIN OF ty_level_column,
        hierarchy TYPE i,
        level     TYPE i,
        key       TYPE i,
        name      TYPE i,
      END OF ty_level_column,
      ty_t_level_column TYPE SORTED TABLE OF ty_level_column WITH UNIQUE KEY hierarchy level.
    TYPES:
      "! A column of a drill-through request (CellRequest): constrained to a key or not.
      BEGIN OF ty_request_column,
        column    TYPE i,
        has_value TYPE abap_bool,
        value     TYPE string,
      END OF ty_request_column,
      ty_t_request_column TYPE SORTED TABLE OF ty_request_column WITH UNIQUE KEY column.
    TYPES:
      "! An item of the select list of a drill-through: a star column or a measure.
      BEGIN OF ty_select_item,
        column  TYPE i,
        measure TYPE i,
      END OF ty_select_item,
      ty_t_select_item TYPE STANDARD TABLE OF ty_select_item WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_column_type,
        table     TYPE string,
        column    TYPE string,
        data_type TYPE string,
        scale     TYPE string,
        length    TYPE string,
      END OF ty_column_type,
      ty_t_column_type TYPE HASHED TABLE OF ty_column_type WITH UNIQUE KEY table column.

    DATA star_columns  TYPE ty_t_star_column.
    DATA level_columns TYPE ty_t_level_column.
    TYPES ty_t_amount TYPE STANDARD TABLE OF decfloat34 WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_group,
        key   TYPE string,
        sums  TYPE ty_t_amount,
        count TYPE i,
      END OF ty_group,
      ty_t_group TYPE HASHED TABLE OF ty_group WITH UNIQUE KEY key.
    TYPES ty_key_set TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    TYPES:
      "! A level column of a pattern constrained to keys (a ListColumnPredicate) or not (all).
      BEGIN OF ty_column_constraint,
        all  TYPE abap_bool,
        keys TYPE ty_key_set,
      END OF ty_column_constraint,
      "! the constraint of each level column of a pattern: the key columns of the levels 1 to level of its filters, in
      "! the order of the filters (the columns of load's GROUP BY)
      ty_t_constraint TYPE STANDARD TABLE OF ty_column_constraint WITH EMPTY KEY,
      ty_t_segment    TYPE STANDARD TABLE OF ty_t_constraint WITH EMPTY KEY.
    TYPES:
      "! The facts of a pattern read so far: their groups (a group of count 0: a cell known to have no facts), the
      "! constraints they were read with (Segment: a key that a segment covers and that has no group has no facts), and
      "! the keys of the cells missed while batching (Batch: one query for all of them, a column's keys the union).
      BEGIN OF ty_cache,
        pattern     TYPE string,
        filters     TYPE ty_t_filter,
        groups      TYPE ty_t_group,
        segments    TYPE ty_t_segment,
        has_pending  TYPE abap_bool,
        pending      TYPE ty_t_constraint,
        pending_keys TYPE ty_key_set,   " the group keys of the cells in pending
      END OF ty_cache.

    DATA cube        TYPE zzxxmla1_cl_schema=>ty_cube.
    DATA hierarchies TYPE zzxxmla1_cl_model=>ty_t_hierarchy.
    DATA measures    TYPE zzxxmla1_cl_model=>ty_t_measure.
    DATA cache       TYPE HASHED TABLE OF ty_cache WITH UNIQUE KEY pattern.
    DATA subcube     TYPE ty_t_predicate.
    DATA batching    TYPE abap_bool.
    DATA dirty       TYPE abap_bool.
    DATA miss_count  TYPE i.
    TYPES:
      BEGIN OF ty_top_answer,
        sql   TYPE string,
        paths TYPE ty_t_paths,
      END OF ty_top_answer.
    "! the answers of top_count by their statement
    DATA top_answers TYPE HASHED TABLE OF ty_top_answer WITH UNIQUE KEY sql.
    "! The facts grouped by the key columns of the operands' levels ("G1_1", "G1_2", ..., "G2_1", ...), with the
    "! filters and the subcube, and the values of the measures ("V1", "V2", ...).
    "! @parameter values | the measures, their positions in the measures; none: only the groups
    METHODS top_facts_sql
      IMPORTING operands      TYPE ty_t_top_operand
                filters       TYPE ty_t_filter
                !values       TYPE ty_t_index
      RETURNING VALUE(result) TYPE string.
    "! The members of an operand: the distinct key columns of its levels in its dimension table ("C1", "C2", ...),
    "! those below its ancestor.
    METHODS operand_sql
      IMPORTING operand       TYPE ty_top_operand
      RETURNING VALUE(result) TYPE string.
    "! The SQL condition of a node of a predicate (the subcube's, a compound slicer's); the hierarchies of its members
    "! are joined as s and the position of the hierarchy.
    METHODS predicate_sql
      IMPORTING predicate     TYPE ty_t_predicate
                index         TYPE i
      CHANGING  joined        TYPE ty_t_index
      RETURNING VALUE(result) TYPE string.
    "! The star of the cube (RolapCube's registration of its levels with RolapStar.Table.makeColumns), made once.
    METHODS make_star.
    "! The star column of a column of a dimension's table, made if it has none yet.
    METHODS star_column
      IMPORTING hierarchy     TYPE i
                column        TYPE string
                name          TYPE string
      RETURNING VALUE(result) TYPE i.
    "! CellRequest.addConstrainedColumn: a column with or without a key. A key replaces none, and a key that differs
    "! from the column's leaves it without (the request is unsatisfiable, which a drill-through does not check).
    CLASS-METHODS constrain
      IMPORTING column    TYPE i
                has_value TYPE abap_bool DEFAULT abap_false
                value     TYPE string OPTIONAL
      CHANGING  request   TYPE ty_t_request_column.
    "! DrillThroughQuerySpec.makeAlias: the name, with _0, _1, ... appended while it is taken.
    CLASS-METHODS alias
      IMPORTING name          TYPE string
      CHANGING  taken         TYPE string_table
      RETURNING VALUE(result) TYPE string.
    "! The database types of the columns of tables and views (what JDBC's ResultSetMetaData reports to the reference).
    CLASS-METHODS column_types
      IMPORTING tables        TYPE string_table
      RETURNING VALUE(result) TYPE ty_t_column_type.
    "! The fact table's foreign key of a hierarchy's dimension as the value of the column it refers to: cast to that
    "! column's type if the two differ (an aDSO's fact column holds a NUMC value as text, the view the number).
    METHODS fact_key
      IMPORTING hierarchy     TYPE i
                types         TYPE ty_t_column_type
      RETURNING VALUE(result) TYPE string.
    "! A database type as the type of a CAST: with its length (and the scale of a decimal) where it has one.
    CLASS-METHODS cast_type
      IMPORTING type          TYPE ty_column_type
      RETURNING VALUE(result) TYPE string.
    "! XmlaHandler.sqlToXsdType: integers and decimals of scale 0 xsd:integer, other decimals xsd:decimal, floating
    "! point numbers xsd:double, anything else xsd:string.
    CLASS-METHODS xsd_type
      IMPORTING type          TYPE ty_column_type
      RETURNING VALUE(result) TYPE string.
    "! A value as TabularRowSet.unparse writes it: a decimal rounded to 4 places (half even), a number without
    "! trailing zeros after the point (XmlaUtil.normalizeNumericString).
    CLASS-METHODS drill_value
      IMPORTING value         TYPE string
                xsd_type      TYPE string
      RETURNING VALUE(result) TYPE string.

    "! The entry of the pattern of filters sorted by hierarchy, made if there is none yet.
    METHODS cache_entry
      IMPORTING filters       TYPE ty_t_filter
      RETURNING VALUE(result) TYPE REF TO ty_cache.
    "! The constraint of a request (CellRequest): each level column of a filter constrained to its key in the filter's
    "! path; the columns of a filter marked any not constrained.
    CLASS-METHODS request_constraint
      IMPORTING filters       TYPE ty_t_filter
      RETURNING VALUE(result) TYPE ty_t_constraint.
    "! A segment holds every group of a constraint: each column of the segment is not constrained or its keys include
    "! the constraint's.
    CLASS-METHODS covers
      IMPORTING segment       TYPE ty_t_constraint
                constraint    TYPE ty_t_constraint
      RETURNING VALUE(result) TYPE abap_bool.
    CLASS-METHODS covered
      IMPORTING segments      TYPE ty_t_segment
                constraint    TYPE ty_t_constraint
      RETURNING VALUE(result) TYPE abap_bool.
    "! The keys of the level columns of a cell's filters (the paths padded to their levels), in the order of the columns.
    CLASS-METHODS request_keys
      IMPORTING filters       TYPE ty_t_filter
      RETURNING VALUE(result) TYPE string_table.
    "! covered for the constraint of one cell, given by its keys.
    CLASS-METHODS covered_keys
      IMPORTING segments      TYPE ty_t_segment
                keys          TYPE string_table
      RETURNING VALUE(result) TYPE abap_bool.
    "! Reads the groups of a constraint into the entry and keeps the constraint as a segment; a column with more keys
    "! than max_constraints is read without constraint.
    METHODS load_segment
      IMPORTING entry      TYPE REF TO ty_cache
                constraint TYPE ty_t_constraint.
    "! The keys of a path, as many as the level (an empty key at the end is kept).
    CLASS-METHODS path_keys
      IMPORTING path          TYPE string
                level         TYPE i
      RETURNING VALUE(result) TYPE string_table.
    "! Groups the facts by the level columns of the filters' hierarchies down to their levels and stores the sums of
    "! all measures; only the facts whose level columns satisfy the constraint.
    METHODS load
      IMPORTING filters       TYPE ty_t_filter
                constraint    TYPE ty_t_constraint
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
    DATA(key) = VALUE string( ).
    LOOP AT <sorted> ASSIGNING <filter>.
      key = key && <filter>-path && zzxxmla1_cl_model=>c_separator.
    ENDLOOP.

    DATA(entry) = cache_entry( <sorted> ).
    ASSIGN entry->groups[ key = key ] TO FIELD-SYMBOL(<group>).
    IF sy-subrc <> 0.
      " recorded in this pass already: 0 again
      IF batching = abap_true AND line_exists( entry->pending_keys[ table_line = key ] ).
        miss_count = miss_count + 1.
        dirty = abap_true.
        RETURN.
      ENDIF.
      DATA(keys) = request_keys( <sorted> ).
      IF covered_keys( segments = entry->segments keys = keys ) = abap_true.
        " read, without facts: kept as a group without any
        INSERT VALUE #( key = key ) INTO TABLE entry->groups.
        result-empty = abap_true.
        RETURN.
      ENDIF.
      miss_count = miss_count + 1.
      IF batching = abap_true.
        " recorded for the next load; 0 for this pass, which is evaluated again
        IF entry->has_pending = abap_false.
          entry->pending = VALUE #( FOR k IN keys ( keys = VALUE #( ( k ) ) ) ).
          entry->has_pending = abap_true.
        ELSE.
          LOOP AT keys INTO DATA(column_key).
            ASSIGN entry->pending[ sy-tabix ]-keys TO FIELD-SYMBOL(<keys>).
            INSERT column_key INTO TABLE <keys>.
          ENDLOOP.
        ENDIF.
        INSERT key INTO TABLE entry->pending_keys.
        dirty = abap_true.
        RETURN.
      ENDIF.
      load_segment( entry = entry constraint = VALUE #( FOR k IN keys ( keys = VALUE #( ( k ) ) ) ) ).
      ASSIGN entry->groups[ key = key ] TO <group>.
      IF sy-subrc <> 0.
        INSERT VALUE #( key = key ) INTO TABLE entry->groups.
        result-empty = abap_true.
        RETURN.
      ENDIF.
    ENDIF.
    IF <group>-count = 0.
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
    CLEAR: cache, dirty, top_answers.
  ENDMETHOD.

  METHOD set_batching.
    me->batching = batching.
  ENDMETHOD.

  METHOD is_dirty.
    result = dirty.
  ENDMETHOD.

  METHOD set_dirty.
    dirty = abap_true.
  ENDMETHOD.

  METHOD get_miss_count.
    result = miss_count.
  ENDMETHOD.

  METHOD load_aggregations.
    IF dirty = abap_false.
      RETURN.
    ENDIF.
    LOOP AT cache ASSIGNING FIELD-SYMBOL(<entry>) WHERE has_pending = abap_true.
      load_segment( entry = REF #( <entry> ) constraint = <entry>-pending ).
      CLEAR: <entry>-pending, <entry>-has_pending, <entry>-pending_keys.
    ENDLOOP.
    dirty = abap_false.
    result = abap_true.
  ENDMETHOD.

  METHOD cache_entry.
    DATA(pattern) = VALUE string( ).
    LOOP AT filters ASSIGNING FIELD-SYMBOL(<filter>).
      pattern = pattern && <filter>-hierarchy && `:` && <filter>-level && `,`.
    ENDLOOP.
    ASSIGN cache[ pattern = pattern ] TO FIELD-SYMBOL(<entry>).
    IF sy-subrc <> 0.
      INSERT VALUE #( pattern = pattern
                      filters = VALUE #( FOR f IN filters ( hierarchy = f-hierarchy level = f-level ) ) )
             INTO TABLE cache ASSIGNING <entry>.
    ENDIF.
    result = REF #( <entry> ).
  ENDMETHOD.

  METHOD request_constraint.
    LOOP AT filters ASSIGNING FIELD-SYMBOL(<filter>).
      IF <filter>-any = abap_true.
        DO <filter>-level TIMES.
          APPEND VALUE #( all = abap_true ) TO result.
        ENDDO.
        CONTINUE.
      ENDIF.
      LOOP AT path_keys( path = <filter>-path level = <filter>-level ) INTO DATA(key).
        APPEND VALUE #( keys = VALUE #( ( key ) ) ) TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD covers.
    result = abap_true.
    LOOP AT constraint ASSIGNING FIELD-SYMBOL(<column>).
      ASSIGN segment[ sy-tabix ] TO FIELD-SYMBOL(<own>).
      IF <own>-all = abap_true.
        CONTINUE.
      ENDIF.
      IF <column>-all = abap_true.
        result = abap_false.
        RETURN.
      ENDIF.
      LOOP AT <column>-keys INTO DATA(key).
        IF NOT line_exists( <own>-keys[ table_line = key ] ).
          result = abap_false.
          RETURN.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD request_keys.
    LOOP AT filters ASSIGNING FIELD-SYMBOL(<filter>).
      APPEND LINES OF path_keys( path = <filter>-path level = <filter>-level ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD covered_keys.
    LOOP AT segments ASSIGNING FIELD-SYMBOL(<segment>).
      result = abap_true.
      LOOP AT keys INTO DATA(key).
        ASSIGN <segment>[ sy-tabix ] TO FIELD-SYMBOL(<column>).
        IF <column>-all = abap_false AND NOT line_exists( <column>-keys[ table_line = key ] ).
          result = abap_false.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD covered.
    LOOP AT segments ASSIGNING FIELD-SYMBOL(<segment>).
      IF covers( segment = <segment> constraint = constraint ) = abap_true.
        result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD load_segment.
    " Aggregation.optimizePredicates: a column of more keys than max_constraints is not constrained
    DATA(segment) = constraint.
    LOOP AT segment ASSIGNING FIELD-SYMBOL(<column>) WHERE all = abap_false.
      IF lines( <column>-keys ) > max_constraints.
        <column>-all = abap_true.
        CLEAR <column>-keys.
      ENDIF.
    ENDLOOP.
    LOOP AT load( filters = entry->filters constraint = segment ) INTO DATA(group).
      " a group read before by another segment is the same
      INSERT group INTO TABLE entry->groups.
    ENDLOOP.
    APPEND segment TO entry->segments.
  ENDMETHOD.

  METHOD path_keys.
    SPLIT path AT zzxxmla1_cl_model=>c_separator INTO TABLE result.
    WHILE lines( result ) < level.
      APPEND `` TO result.
    ENDWHILE.
  ENDMETHOD.

  METHOD predicate_sql.
    DATA(node) = predicate[ index ].
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
          APPEND predicate_sql( EXPORTING predicate = predicate index = child CHANGING joined = joined ) TO parts.
        ENDLOOP.
        IF parts IS INITIAL.
          result = COND #( WHEN node-kind = c_predicate-and THEN `1 = 1` ELSE `1 = 0` ).
        ELSE.
          result = |( { concat_lines_of( table = parts sep = | { node-kind } | ) } )|.
        ENDIF.
      WHEN c_predicate-not.
        result = |NOT ( { predicate_sql( EXPORTING predicate = predicate index = node-children[ 1 ]
                                         CHANGING  joined    = joined ) } )|.
      WHEN c_predicate-value.
        id = node-column-hierarchy.
        IF NOT line_exists( joined[ table_line = id ] ).
          APPEND id TO joined.
        ENDIF.
        DATA(column) = |s{ id }.{ zzxxmla1_cl_sql=>quote( node-column-column ) }|.
        IF node-column-is_null = abap_true.
          result = |{ column } IS NULL|.
        ELSEIF node-column-quoted = abap_true.
          " a string comparison: the column may be a number, so its text is compared
          result = |TO_NVARCHAR( { column } ) = { zzxxmla1_cl_sql=>literal( node-column-value ) }|.
        ELSE.
          result = |{ column } = { node-column-value }|.
        ENDIF.
      WHEN c_predicate-true.
        result = `1 = 1`.
      WHEN OTHERS.
        result = `1 = 0`.
    ENDCASE.
  ENDMETHOD.

  METHOD non_empty_paths.
    DATA(sorted) = filters.
    SORT sorted BY hierarchy ASCENDING.
    " the facts of the other filters' members, any member of the levels marked any; read now unless read already
    DATA(entry) = cache_entry( sorted ).
    DATA(request) = request_constraint( sorted ).
    IF covered( segments = entry->segments constraint = request ) = abap_false.
      load_segment( entry = entry constraint = request ).
    ENDIF.
    DATA tokens TYPE string_table.
    DATA paths TYPE HASHED TABLE OF ty_filter WITH UNIQUE KEY hierarchy.
    LOOP AT entry->groups ASSIGNING FIELD-SYMBOL(<group>) WHERE count > 0.
      " the key: per filter its path (as many keys as its level), as load builds it
      SPLIT <group>-key AT zzxxmla1_cl_model=>c_separator INTO TABLE tokens.
      CLEAR paths.
      DATA(position) = 0.
      DATA(matches) = abap_true.
      LOOP AT sorted INTO DATA(filter).
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

  METHOD operand_sql.
    DATA(hierarchy) = hierarchies[ operand-hierarchy ].
    DATA(columns) = VALUE string_table( ).
    LOOP AT hierarchy-levels INTO DATA(level) TO operand-level.
      APPEND |{ zzxxmla1_cl_sql=>quote( level-key_column ) } AS "C{ sy-tabix }"| TO columns.
      " the order of a level with an ordinal column (one per key, so DISTINCT keeps the members)
      IF level-ordinal_column IS NOT INITIAL.
        APPEND |{ zzxxmla1_cl_sql=>quote( level-ordinal_column ) } AS "O{ sy-tabix }"| TO columns.
      ENDIF.
    ENDLOOP.
    result = |SELECT DISTINCT { concat_lines_of( table = columns sep = `, ` ) } | &&
             |FROM { zzxxmla1_cl_model=>member_table( hierarchy ) }| &&
             COND #( WHEN operand-ancestor_level > 0
                     THEN | WHERE { zzxxmla1_cl_model=>path_condition( hierarchy = hierarchy
                                                                        level_no  = operand-ancestor_level
                                                                        path      = operand-ancestor_path ) }| ).
  ENDMETHOD.

  METHOD operand_counts.
    DATA(counts) = VALUE string_table( ).
    LOOP AT operands INTO DATA(operand).
      DATA(index) = sy-tabix.
      APPEND |( SELECT COUNT( * ) FROM ( { operand_sql( operand ) } ) m{ index } )| TO counts.
    ENDLOOP.
    DATA(rows) = zzxxmla1_cl_sql=>query( sql     = |SELECT { concat_lines_of( table = counts sep = `, ` ) } FROM DUMMY|
                                         columns = lines( counts ) ).
    LOOP AT rows[ 1 ] INTO DATA(count).
      APPEND CONV int8( count ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD top_facts_sql.
    " one join per hierarchy of an operand or a filter, as load joins them
    DATA(source) = |{ zzxxmla1_cl_sql=>quote( cube-fact_table ) } f|.
    DATA(joined_ids) = VALUE ty_t_index( ).
    LOOP AT operands INTO DATA(operand).
      APPEND operand-hierarchy TO joined_ids.
    ENDLOOP.
    LOOP AT filters INTO DATA(filter) WHERE level > 0.
      IF NOT line_exists( joined_ids[ table_line = filter-hierarchy ] ).
        APPEND filter-hierarchy TO joined_ids.
      ENDIF.
    ENDLOOP.
    LOOP AT joined_ids INTO DATA(id).
      source = source && | INNER JOIN { zzxxmla1_cl_sql=>quote( hierarchies[ id ]-dim_table ) } d{ id }| &&
               | ON d{ id }.{ zzxxmla1_cl_sql=>quote( hierarchies[ id ]-key_column ) }| &&
               | = f.{ zzxxmla1_cl_sql=>quote( hierarchies[ id ]-fk_column ) }|.
    ENDLOOP.
    DATA(group_by) = VALUE string_table( ).
    DATA(select_list) = VALUE string_table( ).
    LOOP AT operands INTO operand.
      DATA(index) = sy-tabix.
      LOOP AT hierarchies[ operand-hierarchy ]-levels INTO DATA(level) TO operand-level.
        DATA(level_no) = sy-tabix.
        DATA(column) = |d{ operand-hierarchy }.{ zzxxmla1_cl_sql=>quote( level-key_column ) }|.
        APPEND column TO group_by.
        APPEND |{ column } AS "G{ index }_{ level_no }"| TO select_list.
      ENDLOOP.
    ENDLOOP.
    " the values as load reads them: the sum of the fact column (NULL is 0), or the fact count
    LOOP AT values INTO DATA(measure).
      APPEND COND string( WHEN measures[ measure ]-aggregator = `count` THEN |COUNT( * ) AS "V{ sy-tabix }"|
                          ELSE |COALESCE( SUM( f.{ zzxxmla1_cl_sql=>quote( measures[ measure ]-fact_column ) } ), 0 )| &&
                               | AS "V{ sy-tabix }"| ) TO select_list.
    ENDLOOP.
    DATA(conditions) = VALUE string_table( ).
    LOOP AT filters INTO filter WHERE level > 0.
      DATA(keys) = path_keys( path = filter-path level = filter-level ).
      LOOP AT hierarchies[ filter-hierarchy ]-levels INTO level TO filter-level.
        level_no = sy-tabix.
        APPEND zzxxmla1_cl_sql=>key_condition(
                 column = |d{ filter-hierarchy }.{ zzxxmla1_cl_sql=>quote( level-key_column ) }|
                 key    = keys[ level_no ] ) TO conditions.
      ENDLOOP.
    ENDLOOP.
    IF subcube IS NOT INITIAL.
      DATA subcube_joined TYPE ty_t_index.
      DATA(condition) = predicate_sql( EXPORTING predicate = subcube index = 1 CHANGING joined = subcube_joined ).
      LOOP AT subcube_joined INTO id.
        source = source && | INNER JOIN { zzxxmla1_cl_sql=>quote( hierarchies[ id ]-dim_table ) } s{ id }| &&
                 | ON s{ id }.{ zzxxmla1_cl_sql=>quote( hierarchies[ id ]-key_column ) }| &&
                 | = f.{ zzxxmla1_cl_sql=>quote( hierarchies[ id ]-fk_column ) }|.
      ENDLOOP.
      APPEND condition TO conditions.
    ENDIF.
    result = |SELECT { concat_lines_of( table = select_list sep = `, ` ) } FROM { source }| &&
             COND string( WHEN conditions IS NOT INITIAL
                          THEN | WHERE { concat_lines_of( table = conditions sep = ` AND ` ) }| ) &&
             | GROUP BY { concat_lines_of( table = group_by sep = `, ` ) }|.
  ENDMETHOD.

  METHOD top_count.
    result = ordered_paths( operands      = operands
                            filters       = filters
                            items         = VALUE #( ( measure = measure descending = top ) )
                            limit         = count
                            with_empty    = with_empty
                            tuple_filters = tuple_filters ).
  ENDMETHOD.

  METHOD ordered_paths.
    " the members' crossjoin: per operand its key columns, joined to a grouped fact query on all of them
    DATA(hierarchy_order) = VALUE string_table( ).
    DATA(outer_columns) = VALUE string_table( ).
    DATA(value_join) = VALUE string_table( ).
    DATA(tuple_join) = VALUE string_table( ).
    DATA(from) = ``.
    LOOP AT operands INTO DATA(operand).
      DATA(index) = sy-tabix.
      DO operand-level TIMES.
        DATA(column) = |m{ index }."C{ sy-index }"|.
        APPEND column TO outer_columns.
        " the keys of BW's tables are never NULL; a member with a NULL key would have no facts here
        APPEND |{ column } = g."G{ index }_{ sy-index }"| TO value_join.
        APPEND |{ column } = t."G{ index }_{ sy-index }"| TO tuple_join.
        " hierarchy order: the keys from the first level, NULL first (read_members), a level's ordinal before its key
        IF hierarchies[ operand-hierarchy ]-levels[ sy-index ]-ordinal_column IS NOT INITIAL.
          APPEND |m{ index }."O{ sy-index }" ASC NULLS FIRST| TO hierarchy_order.
        ENDIF.
        APPEND |{ column } ASC NULLS FIRST| TO hierarchy_order.
      ENDDO.
      from = from && COND string( WHEN index > 1 THEN ` CROSS JOIN ` ) && |( { operand_sql( operand ) } ) m{ index }|.
    ENDLOOP.
    " the measures of the items, each once
    DATA(values) = VALUE ty_t_index( ).
    LOOP AT items INTO DATA(item) WHERE operand = 0.
      IF NOT line_exists( values[ table_line = item-measure ] ).
        APPEND item-measure TO values.
      ENDIF.
    ENDLOOP.
    " the values of each tuple from the facts (none: empty, the smallest value); without the empty tuples only those
    " with facts with the tuple filters, which may differ from the values'
    DATA(value_condition) = concat_lines_of( table = value_join sep = ` AND ` ).
    IF with_empty = abap_false AND tuple_filters = filters AND values IS NOT INITIAL.
      from = |{ from } INNER JOIN ( { top_facts_sql( operands = operands filters = filters values = values ) } ) g| &&
             | ON { value_condition }|.
    ELSE.
      IF with_empty = abap_false.
        from = |{ from } INNER JOIN ( { top_facts_sql( operands = operands filters = tuple_filters values = VALUE #( ) ) } )| &&
               | t ON { concat_lines_of( table = tuple_join sep = ` AND ` ) }|.
      ENDIF.
      IF values IS NOT INITIAL.
        from = |{ from } LEFT JOIN ( { top_facts_sql( operands = operands filters = filters values = values ) } ) g| &&
               | ON { value_condition }|.
      ENDIF.
    ENDIF.
    DATA(order_by) = VALUE string_table( ).
    LOOP AT items INTO item.
      DATA(direction) = COND string( WHEN item-descending = abap_true THEN `DESC NULLS LAST` ELSE `ASC NULLS FIRST` ).
      IF item-operand = 0.
        APPEND |g."V{ line_index( values[ table_line = item-measure ] ) }" { direction }| TO order_by.
        CONTINUE.
      ENDIF.
      DATA(key_column) = |m{ item-operand }."C{ item-level }"|.
      " OrderKey of a level with an ordinal column: the ordinal (RolapMemberBase.getOrderKey), then the key
      DATA(ordered_level) = hierarchies[ operands[ item-operand ]-hierarchy ]-levels[ item-level ].
      IF ordered_level-ordinal_column IS NOT INITIAL.
        APPEND |m{ item-operand }."O{ item-level }" { direction }| TO order_by.
      ENDIF.
      IF zzxxmla1_cl_model=>is_numeric_level( hierarchy = hierarchies[ operands[ item-operand ]-hierarchy ]
                                              level_no  = item-level ) = abap_false.
        " Util.caseSensitiveCompareName: ignoring case, then with case
        APPEND |LOWER( { key_column } ) { direction }| TO order_by.
      ENDIF.
      APPEND |{ key_column } { direction }| TO order_by.
    ENDLOOP.
    APPEND LINES OF hierarchy_order TO order_by.
    DATA(sql) = |SELECT { concat_lines_of( table = outer_columns sep = `, ` ) } FROM { from }| &&
                | ORDER BY { concat_lines_of( table = order_by sep = `, ` ) }| &&
                COND string( WHEN limit > 0 THEN | LIMIT { limit }| ).
    READ TABLE top_answers INTO DATA(answer) WITH TABLE KEY sql = sql.
    IF sy-subrc = 0.
      result = answer-paths.
      RETURN.
    ENDIF.

    LOOP AT zzxxmla1_cl_sql=>query( sql = sql columns = lines( outer_columns ) ) INTO DATA(row).
      " per operand the path of its member: its keys from the first level
      DATA(paths) = VALUE string_table( ).
      DATA(position) = 0.
      LOOP AT operands INTO operand.
        DATA(path) = ``.
        DO operand-level TIMES.
          position = position + 1.
          path = COND #( WHEN sy-index = 1 THEN row[ position ]
                         ELSE path && zzxxmla1_cl_model=>c_separator && row[ position ] ).
        ENDDO.
        APPEND path TO paths.
      ENDLOOP.
      APPEND paths TO result.
    ENDLOOP.
    INSERT VALUE #( sql = sql paths = result ) INTO TABLE top_answers.
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
    " the keys of the cells asked for (the segment's column predicates)
    DATA(conditions) = VALUE string_table( ).
    LOOP AT constraint ASSIGNING FIELD-SYMBOL(<column>) WHERE all = abap_false.
      APPEND zzxxmla1_cl_sql=>keys_condition( column = group_by[ sy-tabix ]
                                              keys   = VALUE #( FOR k IN <column>-keys ( k ) ) ) TO conditions.
    ENDLOOP.
    " the subcube: its condition, with the hierarchies of its members joined once more
    IF subcube IS NOT INITIAL.
      DATA joined TYPE ty_t_index.
      DATA(condition) = predicate_sql( EXPORTING predicate = subcube index = 1 CHANGING joined = joined ).
      LOOP AT joined INTO DATA(joined_id).
        source = source && | INNER JOIN { zzxxmla1_cl_sql=>quote( hierarchies[ joined_id ]-dim_table ) } s{ joined_id }| &&
                 | ON s{ joined_id }.{ zzxxmla1_cl_sql=>quote( hierarchies[ joined_id ]-key_column ) }| &&
                 | = f.{ zzxxmla1_cl_sql=>quote( hierarchies[ joined_id ]-fk_column ) }|.
      ENDLOOP.
      APPEND condition TO conditions.
    ENDIF.
    DATA(where) = COND string( WHEN conditions IS NOT INITIAL
                               THEN | WHERE { concat_lines_of( table = conditions sep = ` AND ` ) }| ).
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

  METHOD drill_through.
    make_star( ).

    " the request (RolapAggregationManager.makeCellRequest with an extended context): first the RETURN clause, each
    " level its key column and the column of its names, each measure itself (addNonConstrainingColumns of an
    " OlapElement); these are the drill-through items, the only ones selected
    DATA request TYPE ty_t_request_column.
    DATA drill_items TYPE ty_t_select_item.
    LOOP AT items INTO DATA(item).
      IF item-measure > 0.
        APPEND VALUE #( measure = item-measure ) TO drill_items.
        CONTINUE.
      ENDIF.
      IF item-column IS NOT INITIAL.
        " a column of the dimension's table (RolapDrillThroughAttributeColumn), registered after the levels'
        DATA(attribute_column) = star_column( hierarchy = item-hierarchy column = item-column name = item-name ).
        constrain( EXPORTING column = attribute_column CHANGING request = request ).
        APPEND VALUE #( column = attribute_column ) TO drill_items.
        CONTINUE.
      ENDIF.
      DATA(level_column) = level_columns[ hierarchy = item-hierarchy level = item-level ].
      constrain( EXPORTING column = level_column-key CHANGING request = request ).
      APPEND VALUE #( column = level_column-key ) TO drill_items.
      IF level_column-name > 0.
        constrain( EXPORTING column = level_column-name CHANGING request = request ).
        APPEND VALUE #( column = level_column-name ) TO drill_items.
      ENDIF.
    ENDLOOP.
    " then per member the levels below it, not constrained (addNonConstrainingColumns), and its level and the levels
    " of its ancestors up to a unique level, constrained to their keys (LevelReader.constrainRequest); with a RETURN
    " clause an All member adds nothing
    LOOP AT members INTO DATA(member).
      IF items IS NOT INITIAL AND member-level = 0.
        CONTINUE.
      ENDIF.
      DATA(levels) = hierarchies[ member-hierarchy ]-levels.
      DATA(below) = lines( levels ).
      WHILE below > member-level.
        level_column = level_columns[ hierarchy = member-hierarchy level = below ].
        constrain( EXPORTING column = level_column-key CHANGING request = request ).
        IF level_column-name > 0.
          constrain( EXPORTING column = level_column-name CHANGING request = request ).
        ENDIF.
        below = below - 1.
      ENDWHILE.
      SPLIT member-path AT zzxxmla1_cl_model=>c_separator INTO TABLE DATA(keys).
      DATA(current) = member-level.
      WHILE current > 0.
        level_column = level_columns[ hierarchy = member-hierarchy level = current ].
        constrain( EXPORTING column    = level_column-key
                             has_value = abap_true
                             value     = COND #( WHEN current <= lines( keys ) THEN keys[ current ] )
                   CHANGING  request   = request ).
        IF level_column-name > 0.
          constrain( EXPORTING column = level_column-name CHANGING request = request ).
        ENDIF.
        IF levels[ current ]-unique_members = abap_true.
          EXIT.
        ENDIF.
        current = current - 1.
      ENDWHILE.
    ENDLOOP.

    " the names of the columns (computeDistinctColumnNames): of the request's columns in the order of the star, then
    " of the cell's measure
    DATA taken TYPE string_table.
    DATA aliases TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    LOOP AT request INTO DATA(request_column).
      APPEND alias( EXPORTING name = star_columns[ request_column-column ]-name CHANGING taken = taken ) TO aliases.
    ENDLOOP.
    DATA(measure_alias) = alias( EXPORTING name = measures[ measure ]-name CHANGING taken = taken ).
    DATA(drill_measures) = VALUE ty_t_select_item( FOR d IN drill_items WHERE ( measure > 0 ) ( d ) ).

    " the items in the order of the select list (getItems): the drill-through items, then the other columns and the
    " measures (the drill-through measures, else the cell's)
    DATA(rest) = VALUE ty_t_select_item( FOR r IN request ( column = r-column ) ).
    IF drill_measures IS INITIAL.
      APPEND VALUE #( measure = measure ) TO rest.
    ELSE.
      APPEND LINES OF drill_measures TO rest.
    ENDIF.
    DATA ordered TYPE ty_t_select_item.
    LOOP AT drill_items INTO DATA(drill_item).
      READ TABLE rest TRANSPORTING NO FIELDS WITH KEY column = drill_item-column measure = drill_item-measure.
      IF sy-subrc = 0.
        DELETE rest INDEX sy-tabix.
        APPEND drill_item TO ordered.
      ENDIF.
    ENDLOOP.
    APPEND LINES OF rest TO ordered.

    " the types of the columns as the database reports them: of the fact table and of the tables of the request
    DATA tables TYPE string_table.
    APPEND cube-fact_table TO tables.
    LOOP AT request INTO request_column.
      DATA(dim_table) = hierarchies[ star_columns[ request_column-column ]-hierarchy ]-dim_table.
      IF NOT line_exists( tables[ table_line = dim_table ] ).
        APPEND dim_table TO tables.
      ENDIF.
    ENDLOOP.
    DATA(types) = column_types( tables ).

    " the statement: a column of the star is selected (and ordered by) if it is part of the select, a constrained
    " one restricts the rows. The table of a column is joined only if the column is selected or restricts the rows,
    " and the column the dimension's foreign key refers to is read from the fact table: BW has a SID (and on an aDSO a
    " master data value) for every value of a fact, so the join would not remove a row.
    DATA select_list TYPE string_table.
    DATA order_by TYPE string_table.
    DATA conditions TYPE string_table.
    DATA joins TYPE ty_t_index.
    DATA sources TYPE STANDARD TABLE OF ty_column_type WITH EMPTY KEY.   " table and column of each select item
    LOOP AT ordered INTO DATA(select_item).
      IF select_item-measure > 0.
        IF drill_measures IS NOT INITIAL AND NOT line_exists( drill_measures[ measure = select_item-measure ] ).
          CONTINUE.
        ENDIF.
        DATA(fact_column) = measures[ select_item-measure ]-fact_column.
        " the measure's alias, made unique against the selected columns (getMeasureAlias)
        DATA(name) = COND string( WHEN drill_measures IS NOT INITIAL THEN measures[ select_item-measure ]-name
                                  ELSE measure_alias ).
        DATA(maybe) = name.
        DATA(suffix) = 0.
        DO.
          DATA(clash) = abap_false.
          LOOP AT request INTO request_column.
            IF aliases[ sy-tabix ] = maybe
                AND ( drill_items IS INITIAL OR line_exists( drill_items[ column = request_column-column ] ) ).
              clash = abap_true.
              EXIT.
            ENDIF.
          ENDLOOP.
          IF clash = abap_false.
            EXIT.
          ENDIF.
          maybe = |{ name }_{ suffix }|.
          suffix = suffix + 1.
        ENDDO.
        APPEND COND string( WHEN fact_column IS INITIAL THEN `1`
                            ELSE |f.{ zzxxmla1_cl_sql=>quote( fact_column ) }| ) TO select_list.
        APPEND VALUE #( name = maybe ) TO result-columns.
        APPEND VALUE #( table = cube-fact_table column = fact_column ) TO sources.
        CONTINUE.
      ENDIF.
      DATA(star) = star_columns[ select_item-column ].
      DATA(on_fact) = xsdbool( star-column = hierarchies[ star-hierarchy ]-key_column ).
      DATA(expression) = COND string(
        WHEN on_fact = abap_true THEN fact_key( hierarchy = star-hierarchy types = types )
        ELSE |d{ star-hierarchy }.{ zzxxmla1_cl_sql=>quote( star-column ) }| ).
      READ TABLE request INTO request_column WITH TABLE KEY column = select_item-column.
      DATA(position) = sy-tabix.
      DATA(selected) = xsdbool( drill_items IS INITIAL OR line_exists( drill_items[ column = select_item-column ] ) ).
      IF on_fact = abap_false AND ( selected = abap_true OR request_column-has_value = abap_true )
          AND NOT line_exists( joins[ table_line = star-hierarchy ] ).
        APPEND star-hierarchy TO joins.
      ENDIF.
      IF request_column-has_value = abap_true.
        APPEND zzxxmla1_cl_sql=>key_condition( column = expression key = request_column-value ) TO conditions.
      ENDIF.
      IF selected = abap_false.
        CONTINUE.
      ENDIF.
      APPEND expression TO select_list.
      APPEND expression TO order_by.
      APPEND VALUE #( name = aliases[ position ] ) TO result-columns.
      APPEND VALUE #( table = hierarchies[ star-hierarchy ]-dim_table column = star-column ) TO sources.
    ENDLOOP.
    IF select_list IS INITIAL.
      RETURN.
    ENDIF.

    DATA(source) = |{ zzxxmla1_cl_sql=>quote( cube-fact_table ) } f|.
    LOOP AT joins INTO DATA(id).
      source = source && | INNER JOIN { zzxxmla1_cl_sql=>quote( hierarchies[ id ]-dim_table ) } d{ id }| &&
               | ON d{ id }.{ zzxxmla1_cl_sql=>quote( hierarchies[ id ]-key_column ) }| &&
               | = f.{ zzxxmla1_cl_sql=>quote( hierarchies[ id ]-fk_column ) }|.
    ENDLOOP.
    " the subcube and the positions of a compound slicer (RolapCell.addSubcubePredicates), with the hierarchies of
    " their members joined once more
    DATA joined TYPE ty_t_index.
    IF subcube IS NOT INITIAL.
      APPEND predicate_sql( EXPORTING predicate = subcube index = 1 CHANGING joined = joined ) TO conditions.
    ENDIF.
    IF slicer IS NOT INITIAL.
      APPEND predicate_sql( EXPORTING predicate = slicer index = 1 CHANGING joined = joined ) TO conditions.
    ENDIF.
    LOOP AT joined INTO id.
      source = source && | INNER JOIN { zzxxmla1_cl_sql=>quote( hierarchies[ id ]-dim_table ) } s{ id }| &&
               | ON s{ id }.{ zzxxmla1_cl_sql=>quote( hierarchies[ id ]-key_column ) }| &&
               | = f.{ zzxxmla1_cl_sql=>quote( hierarchies[ id ]-fk_column ) }|.
    ENDLOOP.
    " which values are NULL, one character per column (the SQL reads a NULL as an empty string)
    DATA(null_flags) = concat_lines_of(
      table = VALUE string_table( FOR s IN select_list ( |CASE WHEN { s } IS NULL THEN '1' ELSE '0' END| ) )
      sep   = ` || ` ).
    DATA(sql) = |SELECT { concat_lines_of( table = select_list sep = `, ` ) }, { null_flags } FROM { source }| &&
                COND string( WHEN conditions IS NOT INITIAL
                             THEN | WHERE { concat_lines_of( table = conditions sep = ` AND ` ) }| ) &&
                COND string( WHEN order_by IS NOT INITIAL
                             THEN | ORDER BY { concat_lines_of( table = order_by sep = `, ` ) }| ) &&
                COND string( WHEN max_rows > 0 THEN | LIMIT { max_rows }| ).

    " the XML schema types of the columns: of a key read from the fact table the type of the dimension's column
    LOOP AT result-columns ASSIGNING FIELD-SYMBOL(<column>).
      DATA(table_column) = sources[ sy-tabix ].
      READ TABLE types INTO DATA(type) WITH TABLE KEY table = table_column-table column = table_column-column.
      <column>-xsd_type = COND #( WHEN sy-subrc = 0 THEN xsd_type( type )
                                  WHEN table_column-column IS INITIAL THEN `xsd:integer`
                                  ELSE `xsd:string` ).
    ENDLOOP.

    " the rows, the first FIRSTROWSET of them skipped (SqlStatement.execute); the last column flags the NULL values
    result-rows = zzxxmla1_cl_sql=>query( sql = sql columns = lines( select_list ) + 1 ).
    IF first_row > 0.
      DELETE result-rows TO first_row.
    ENDIF.
    LOOP AT result-rows ASSIGNING FIELD-SYMBOL(<row>).
      APPEND <row>[ lines( <row> ) ] TO result-nulls.
      DELETE <row> INDEX lines( <row> ).
      LOOP AT <row> ASSIGNING FIELD-SYMBOL(<value>).
        <value> = drill_value( value = <value> xsd_type = result-columns[ sy-tabix ]-xsd_type ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD make_star.
    IF star_columns IS NOT INITIAL.
      RETURN.
    ENDIF.
    LOOP AT hierarchies INTO DATA(hierarchy).
      DATA(id) = sy-tabix.
      LOOP AT hierarchy-levels INTO DATA(level).
        DATA(level_column) = VALUE ty_level_column( hierarchy = id level = sy-tabix ).
        " a level with a name column: that column first, named as the level, then its key column, "<level> (Key)"
        IF level-name_column IS NOT INITIAL AND level-name_column <> level-key_column.
          level_column-name = star_column( hierarchy = id column = level-name_column name = level-level_name ).
          level_column-key = star_column( hierarchy = id column = level-key_column
                                          name      = |{ level-level_name } (Key)| ).
        ELSE.
          level_column-key = star_column( hierarchy = id column = level-key_column name = level-level_name ).
        ENDIF.
        INSERT level_column INTO TABLE level_columns.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD star_column.
    " a column of the dimension's table is one star column, whichever level uses it
    DATA(dimension) = hierarchies[ hierarchy ]-dim_name.
    READ TABLE star_columns TRANSPORTING NO FIELDS WITH KEY dimension = dimension column = column.
    IF sy-subrc = 0.
      result = sy-tabix.
      RETURN.
    ENDIF.
    READ TABLE hierarchies TRANSPORTING NO FIELDS WITH KEY dim_name = dimension.
    DATA(first) = sy-tabix.
    APPEND VALUE #( dimension = dimension hierarchy = first column = column name = name ) TO star_columns.
    result = lines( star_columns ).
  ENDMETHOD.

  METHOD constrain.
    READ TABLE request ASSIGNING FIELD-SYMBOL(<column>) WITH TABLE KEY column = column.
    IF sy-subrc <> 0.
      INSERT VALUE #( column = column has_value = has_value value = value ) INTO TABLE request.
    ELSEIF <column>-has_value = abap_false.
      <column>-has_value = has_value.
      <column>-value = value.
    ELSEIF has_value = abap_true AND value <> <column>-value.
      CLEAR: <column>-has_value, <column>-value.
    ENDIF.
  ENDMETHOD.

  METHOD alias.
    result = name.
    DATA(suffix) = 0.
    WHILE line_exists( taken[ table_line = result ] ).
      result = |{ name }_{ suffix }|.
      suffix = suffix + 1.
    ENDWHILE.
    APPEND result TO taken.
  ENDMETHOD.

  METHOD column_types.
    DATA(names) = concat_lines_of( table = VALUE string_table( FOR t IN tables ( zzxxmla1_cl_sql=>literal( t ) ) )
                                   sep   = `, ` ).
    DATA(sql) = |SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE_NAME, TO_NVARCHAR( SCALE ), TO_NVARCHAR( LENGTH ) | &&
                |FROM SYS.TABLE_COLUMNS | &&
                |WHERE SCHEMA_NAME = CURRENT_SCHEMA AND TABLE_NAME IN ( { names } ) UNION ALL | &&
                |SELECT VIEW_NAME, COLUMN_NAME, DATA_TYPE_NAME, TO_NVARCHAR( SCALE ), TO_NVARCHAR( LENGTH ) | &&
                |FROM SYS.VIEW_COLUMNS | &&
                |WHERE SCHEMA_NAME = CURRENT_SCHEMA AND VIEW_NAME IN ( { names } )|.
    LOOP AT zzxxmla1_cl_sql=>query( sql = sql columns = 5 ) INTO DATA(row).
      INSERT VALUE #( table = row[ 1 ] column = row[ 2 ] data_type = row[ 3 ] scale = row[ 4 ] length = row[ 5 ] )
             INTO TABLE result.
    ENDLOOP.
  ENDMETHOD.

  METHOD fact_key.
    DATA(dimension) = hierarchies[ hierarchy ].
    result = |f.{ zzxxmla1_cl_sql=>quote( dimension-fk_column ) }|.
    READ TABLE types INTO DATA(key_type) WITH TABLE KEY table = dimension-dim_table column = dimension-key_column.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    READ TABLE types INTO DATA(fk_type) WITH TABLE KEY table = cube-fact_table column = dimension-fk_column.
    IF sy-subrc = 0 AND fk_type-data_type = key_type-data_type.
      RETURN.
    ENDIF.
    result = |CAST( { result } AS { cast_type( key_type ) } )|.
  ENDMETHOD.

  METHOD cast_type.
    result = type-data_type.
    CASE type-data_type.
      WHEN `DECIMAL`.
        IF type-scale IS NOT INITIAL.
          result = |DECIMAL( { type-length }, { type-scale } )|.
        ENDIF.
      WHEN `NVARCHAR` OR `VARCHAR` OR `NCHAR` OR `CHAR` OR `ALPHANUM` OR `VARBINARY`.
        result = |{ type-data_type }( { type-length } )|.
    ENDCASE.
  ENDMETHOD.

  METHOD xsd_type.
    CASE type-data_type.
      WHEN `INTEGER` OR `SMALLINT` OR `TINYINT` OR `BIGINT`.
        result = `xsd:integer`.
      WHEN `DECIMAL` OR `SMALLDECIMAL`.
        result = COND #( WHEN type-scale = `0` THEN `xsd:integer` ELSE `xsd:decimal` ).
      WHEN `DOUBLE` OR `REAL` OR `FLOAT`.
        result = `xsd:double`.
      WHEN OTHERS.
        result = `xsd:string`.
    ENDCASE.
  ENDMETHOD.

  METHOD drill_value.
    result = value.
    IF xsd_type = `xsd:string` OR result IS INITIAL.
      RETURN.
    ENDIF.
    IF xsd_type = `xsd:decimal`.
      IF strlen( substring_after( val = result sub = `.` ) ) > 4.
        DATA(rounded) = round( val = CONV decfloat34( result ) dec = 4 mode = cl_abap_math=>round_half_even ).
        result = |{ rounded DECIMALS = 4 }|.
      ENDIF.
    ENDIF.
    " normalizeNumericString: the zeros after the point, then the point
    IF result CA `.` AND result NA `Ee`.
      WHILE substring( val = result off = strlen( result ) - 1 len = 1 ) = `0`.
        result = substring( val = result len = strlen( result ) - 1 ).
      ENDWHILE.
      IF substring( val = result off = strlen( result ) - 1 len = 1 ) = `.`.
        result = substring( val = result len = strlen( result ) - 1 ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
