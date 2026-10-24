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
"! Query planning (docs/query-planning.md), our addition: the reference evaluates every axis and every cell through
"! RolapEvaluator. The planner marks every node of a resolved query (ZZXXMLA1_CL_MDX_VALIDATOR) as
"! - static: answered by the schema and member reads (literals, elements, member functions that read no facts);
"! - relational: answered by grouped SQL over the facts (a stored measure where a value is wanted, NonEmpty,
"!   NonEmptyCrossJoin, the native TopCount, Order and Filter);
"! - computed: for the evaluator (calculated and null members, operators and value functions, sets that depend on
"!   values, anything not known here).
"! A node is the highest mark of its arguments and its own, but for TopCount, Order and Filter, whose value arguments SQL
"! answers. Relational is computed where a calculated member of the slicer is in the context. Besides its mark a
"! member, tuple or set node knows whether a calculated member can be among its members (WITH MEMBER, AllMembers,
"! AddCalculatedMembers, DrilldownLevel with INCLUDE_CALC_MEMBERS, VisualTotals, the current member of a hierarchy with
"! calculated members). The null member never reaches a cell from an axis or the slicer: they are sets, and {} leaves
"! out the tuples with it (SetFunDef), so member navigation is static.
"! The plan of a query: the mark of each axis (a NON EMPTY one at least relational), of the slicer and of the cells
"! (static: no cell property shows a value, no axis is NON EMPTY and no calculated member is in the context, as
"! cells_needed of ZZXXMLA1_CL_MDX_ENGINE; relational: no calculated member in the context, as fast_cells; else
"! computed). The marks are kept here by node; the tree is not changed. ZZXXMLA1_CL_MDX_ENGINE answers a query whose
"! plan is relational with one grouped read of its cells (its switch planning).
CLASS zzxxmla1_cl_mdx_planner DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_node TYPE REF TO zzxxmla1_cl_mdx_node.
    CONSTANTS:
      BEGIN OF c_mark,
        static     TYPE string VALUE `STATIC`,
        relational TYPE string VALUE `RELATIONAL`,
        computed   TYPE string VALUE `COMPUTED`,
      END OF c_mark.
    TYPES:
      BEGIN OF ty_axis_plan,
        ordinal TYPE i,
        mark    TYPE string,
      END OF ty_axis_plan,
      ty_t_axis_plan TYPE STANDARD TABLE OF ty_axis_plan WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_plan,
        axes   TYPE ty_t_axis_plan,   " in the order of the query's axes
        slicer TYPE string,           " empty without a slicer
        cells  TYPE string,
        query  TYPE string,           " the highest mark of the axes, the slicer and the cells
      END OF ty_plan.

    "! @parameter schema_reader | the reader the query was resolved with: it holds the query's calculated members
    METHODS constructor
      IMPORTING schema_reader TYPE REF TO zzxxmla1_cl_mdx_schema_reader.
    "! The plan of a resolved query; every node of its axes, slicer and formulas is marked.
    METHODS plan
      IMPORTING query         TYPE zzxxmla1_cl_mdx_parser=>ty_query
      RETURNING VALUE(result) TYPE ty_plan.
    "! The mark of a resolved node (marked now if plan did not reach it).
    METHODS get_mark
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE string.
    "! The condition of Filter(set, condition) that SQL answers (RolapNativeFilter, RolapNativeSql's booleanCompiler,
    "! a part of it): AND and OR of comparisons (<, <=, >, >=, =, <>) of numbers made of stored measures, decimal
    "! numbers, +, - and *, in parentheses or not. Not division (by zero MDX gives infinity, SQL an error), NOT and
    "! IsEmpty (true for an empty cell), calculated measures. Only a condition that is false for every tuple without
    "! facts in the context, where every stored measure is empty: a comparison with an empty side is false
    "! (BooleanNull), * is empty with one empty side, + and - with two, AND is false with one false side, OR with
    "! two. So the groups of the facts that meet it (the tuples with facts) are the tuples the interpreted Filter
    "! keeps. None for any other condition.
    CLASS-METHODS filter_condition
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_facts=>ty_t_condition.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_marked,
        node       TYPE ty_node,
        mark       TYPE string,
        "! a member, tuple or set: a calculated member can be among its members
        calculated TYPE abap_bool,
      END OF ty_marked.
    " the categories of olap.Category, as zzxxmla1_cl_mdx_type=>c_category
    TYPES ty_category TYPE i.

    DATA schema_reader TYPE REF TO zzxxmla1_cl_mdx_schema_reader.
    DATA marked TYPE HASHED TABLE OF ty_marked WITH UNIQUE KEY node.
    "! the hierarchies with calculated members of the query
    DATA calculated_hierarchies TYPE SORTED TABLE OF i WITH UNIQUE KEY table_line.
    "! false while a calculated member of the slicer is in the context: relational nodes are computed then
    DATA plain_context TYPE abap_bool VALUE abap_true.

    METHODS mark
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_marked.
    METHODS mark_call
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_marked.
    "! The mark of a function that SQL answers when its arguments are static or relational.
    METHODS relational
      IMPORTING args_mark     TYPE string
      RETURNING VALUE(result) TYPE string.
    "! TopCount / BottomCount(set, count, value) whose value is a stored measure and count a static number
    "! (RolapNativeTopCount).
    METHODS is_native_top_count
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE abap_bool.
    "! Order(set, key, BASC | BDESC, ...) whose keys are stored measures or OrderKey calls (native_order of
    "! ZZXXMLA1_CL_MDX_ENGINE).
    METHODS is_native_order
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE abap_bool.
    METHODS is_stored_measure
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE abap_bool.
    "! A node of filter_condition, appended to the condition (an operation before its arguments).
    "! @parameter logical | a condition, else a number
    "! @parameter empty | a condition: false for a tuple without facts; a number: empty for it
    CLASS-METHODS condition_node
      IMPORTING node      TYPE ty_node
                logical   TYPE abap_bool
      EXPORTING found     TYPE abap_bool
                !empty    TYPE abap_bool
      CHANGING  condition TYPE zzxxmla1_cl_mdx_facts=>ty_t_condition.
    "! A calculated member of the query is in the hierarchy (-1: in any).
    METHODS has_calculated
      IMPORTING hierarchy     TYPE i
      RETURNING VALUE(result) TYPE abap_bool.
    "! The category a function's signature declares for its argument at the index, without the Constant flag; 0 if
    "! it declares none.
    CLASS-METHODS parameter_category
      IMPORTING node          TYPE ty_node
                index         TYPE i
      RETURNING VALUE(result) TYPE ty_category.
    CLASS-METHODS is_scalar_category
      IMPORTING category      TYPE ty_category
      RETURNING VALUE(result) TYPE abap_bool.
    "! A cell property shows the cells' values (VALUE, FORMATTED_VALUE, FORMAT_STRING; without any, the first two).
    CLASS-METHODS cells_shown
      IMPORTING cell_properties TYPE string_table
      RETURNING VALUE(result)   TYPE abap_bool.
    CLASS-METHODS higher
      IMPORTING mark1         TYPE string
                mark2         TYPE string
      RETURNING VALUE(result) TYPE string.
    CLASS-METHODS rank
      IMPORTING mark          TYPE string
      RETURNING VALUE(result) TYPE i.
ENDCLASS.

CLASS zzxxmla1_cl_mdx_planner IMPLEMENTATION.

  METHOD constructor.
    me->schema_reader = schema_reader.
  ENDMETHOD.

  METHOD plan.
    CLEAR: marked, calculated_hierarchies.
    DATA(hierarchy_ids) = VALUE int4_table( ( zzxxmla1_cl_mdx_schema_reader=>c_measures ) ).
    LOOP AT schema_reader->get_hierarchies( ) INTO DATA(hierarchy).
      APPEND hierarchy-id TO hierarchy_ids.
    ENDLOOP.
    LOOP AT hierarchy_ids INTO DATA(hierarchy_id).
      IF schema_reader->get_calculated_members( hierarchy_id ) IS NOT INITIAL.
        INSERT hierarchy_id INTO TABLE calculated_hierarchies.
      ENDIF.
    ENDLOOP.

    " the slicer in the default context (its default members are stored), then the axes in the slicer's
    DATA(calculated) = abap_false.
    plain_context = abap_true.
    IF query-slicer IS BOUND.
      DATA(slicer) = mark( query-slicer ).
      result-slicer = slicer-mark.
      calculated = slicer-calculated.
      plain_context = xsdbool( slicer-calculated = abap_false ).
    ENDIF.
    DATA(axes) = VALUE string_table( ).
    LOOP AT query-axes INTO DATA(axis).
      DATA(axis_marked) = mark( axis-expression ).
      APPEND axis_marked-mark TO axes.
      IF axis_marked-calculated = abap_true.
        calculated = abap_true.
      ENDIF.
    ENDLOOP.
    LOOP AT query-formulas INTO DATA(formula).
      mark( formula-expression ).
      LOOP AT formula-properties INTO DATA(property).
        mark( property-expression ).
      ENDLOOP.
    ENDLOOP.

    DATA(non_empty) = xsdbool( line_exists( query-axes[ non_empty = abap_true ] ) ).
    IF calculated = abap_true.
      result-cells = c_mark-computed.
    ELSEIF non_empty = abap_false AND cells_shown( query-cell_properties ) = abap_false.
      result-cells = c_mark-static.
    ELSE.
      result-cells = c_mark-relational.
    ENDIF.

    " a NON EMPTY axis is NonEmpty(axis, {the query's measures}) (Query.compile): grouped SQL unless its cells are
    " computed
    result-query = higher( mark1 = result-cells mark2 = result-slicer ).
    LOOP AT query-axes INTO axis.
      DATA(axis_mark) = axes[ sy-tabix ].
      IF axis-non_empty = abap_true.
        axis_mark = COND #( WHEN result-cells = c_mark-computed THEN c_mark-computed
                            ELSE higher( mark1 = axis_mark mark2 = c_mark-relational ) ).
      ENDIF.
      APPEND VALUE #( ordinal = axis-ordinal mark = axis_mark ) TO result-axes.
      result-query = higher( mark1 = result-query mark2 = axis_mark ).
    ENDLOOP.
  ENDMETHOD.

  METHOD get_mark.
    result = mark( node )-mark.
  ENDMETHOD.

  METHOD mark.
    READ TABLE marked WITH TABLE KEY node = node INTO result.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.
    result-node = node.
    CASE node->kind.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-literal OR zzxxmla1_cl_mdx_node=>c_kind-level
        OR zzxxmla1_cl_mdx_node=>c_kind-hierarchy OR zzxxmla1_cl_mdx_node=>c_kind-dimension.
        result-mark = c_mark-static.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-member.
        " a calculated member's value is its formula; the null member's cells are null
        result-calculated = node->element-member-calculated.
        result-mark = COND #( WHEN node->element-member-calculated = abap_true OR node->element-member-is_null = abap_true
                              THEN c_mark-computed ELSE c_mark-static ).
      WHEN zzxxmla1_cl_mdx_node=>c_kind-named_set.
        " a named set is its expression, evaluated in the slicer's context
        DATA(expression) = mark( node->set_expression ).
        result-mark = expression-mark.
        result-calculated = expression-calculated.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
        result = mark_call( node ).
      WHEN OTHERS.
        " not resolved
        result-mark = c_mark-computed.
    ENDCASE.
    INSERT result INTO TABLE marked.
  ENDMETHOD.

  METHOD mark_call.
    result-node = node.
    DATA(type) = node->get_type( ).
    DATA(is_set) = xsdbool( type IS BOUND AND type->is_set( ) = abap_true ).

    " the arguments: a member, tuple, hierarchy or dimension where a value is wanted is the cell of the context with
    " it, a group of the facts if it is stored
    DATA(args_mark) = c_mark-static.
    LOOP AT node->args INTO DATA(arg).
      DATA(index) = sy-tabix.
      DATA(arg_marked) = mark( arg ).
      DATA(arg_type) = arg->get_type( ).
      DATA(arg_category) = COND ty_category( WHEN arg_type IS BOUND THEN arg_type->category( ) ).
      DATA(category) = parameter_category( node = node index = index ).
      DATA(arg_mark) = arg_marked-mark.
      IF is_scalar_category( category ) = abap_true
         AND ( arg_category = zzxxmla1_cl_mdx_type=>c_category-member
               OR arg_category = zzxxmla1_cl_mdx_type=>c_category-tuple
               OR arg_category = zzxxmla1_cl_mdx_type=>c_category-hierarchy
               OR arg_category = zzxxmla1_cl_mdx_type=>c_category-dimension ).
        arg_mark = higher( mark1 = arg_mark mark2 = relational( c_mark-static ) ).
      ELSEIF arg_category = zzxxmla1_cl_mdx_type=>c_category-member
          OR arg_category = zzxxmla1_cl_mdx_type=>c_category-tuple
          OR arg_category = zzxxmla1_cl_mdx_type=>c_category-set.
        " the members it gives
        IF arg_marked-calculated = abap_true.
          result-calculated = abap_true.
        ENDIF.
      ELSEIF ( arg_category = zzxxmla1_cl_mdx_type=>c_category-hierarchy
               OR arg_category = zzxxmla1_cl_mdx_type=>c_category-dimension )
             AND ( category = zzxxmla1_cl_mdx_type=>c_category-member
                   OR category = zzxxmla1_cl_mdx_type=>c_category-tuple
                   OR category = zzxxmla1_cl_mdx_type=>c_category-set ).
        " a hierarchy where a member is wanted is its current member
        IF has_calculated( arg_type->get_hierarchy( ) ) = abap_true.
          result-calculated = abap_true.
        ENDIF.
      ENDIF.
      args_mark = higher( mark1 = args_mark mark2 = arg_mark ).
    ENDLOOP.

    DATA(name) = to_upper( node->name ).
    DATA(hierarchy) = COND i( WHEN type IS BOUND THEN type->get_hierarchy( ) ELSE zzxxmla1_cl_mdx_type=>c_none ).
    IF node->fun_def-implementation = `CrossJoinFunDef`
       OR ( is_set = abap_true AND ( name = `+` OR name = `-` ) ).
      " CrossJoin, *, the union and the difference of sets
      result-mark = args_mark.
      RETURN.
    ENDIF.
    IF node->syntax = zzxxmla1_cl_mdx_node=>c_syntax-empty.
      " an argument left out
      result-mark = c_mark-static.
      RETURN.
    ENDIF.
    CASE name.
      WHEN `{}` OR `()` OR `:` OR `CROSSJOIN` OR `CHILDREN` OR `MEMBERS` OR `PARENT` OR `FIRSTCHILD` OR `LASTCHILD`
        OR `FIRSTSIBLING` OR `LASTSIBLING` OR `NEXTMEMBER` OR `PREVMEMBER` OR `LAG` OR `LEAD` OR `SIBLINGS`
        OR `ANCESTOR` OR `ANCESTORS` OR `ASCENDANTS` OR `COUSIN` OR `DESCENDANTS` OR `HIERARCHIZE` OR `DRILLDOWNMEMBER`
        OR `UNION` OR `EXCEPT` OR `INTERSECT` OR `HEAD` OR `TAIL` OR `DISTINCT` OR `SUBSET` OR `ITEM` OR `DEFAULTMEMBER`
        OR `LEVEL` OR `LEVELS` OR `HIERARCHY` OR `DIMENSION` OR `NAME` OR `UNIQUENAME` OR `CAPTION` OR `ORDINAL`
        OR `ORDERKEY` OR `PROPERTIES` OR `CURRENTDATEMEMBER` OR `NATIVIZESET`
        OR `PARALLELPERIOD` OR `OPENINGPERIOD` OR `CLOSINGPERIOD` OR `PERIODSTODATE`
        OR `YTD` OR `QTD` OR `MTD` OR `WTD`.
        " member reads: the schema's members, no facts. Without a member argument the time functions take the current
        " member of the time hierarchy: the slicer's or the default member on an axis, inside a formula its parent is
        " computed
        result-mark = args_mark.
      WHEN `CURRENTMEMBER`.
        " on an axis the slicer's or the default member, in an iteration the current tuple's
        result-mark = args_mark.
        IF has_calculated( hierarchy ) = abap_true.
          result-calculated = abap_true.
        ENDIF.
      WHEN `ALLMEMBERS` OR `ADDCALCULATEDMEMBERS` OR `CALCULATEDCHILD`.
        " with the calculated members of the hierarchy
        result-mark = args_mark.
        IF has_calculated( hierarchy ) = abap_true.
          result-calculated = abap_true.
        ENDIF.
      WHEN `DRILLDOWNLEVEL`.
        result-mark = args_mark.
        LOOP AT node->args INTO arg.
          IF arg->kind = zzxxmla1_cl_mdx_node=>c_kind-literal AND to_upper( arg->value ) = `INCLUDE_CALC_MEMBERS`
             AND has_calculated( hierarchy ) = abap_true.
            result-calculated = abap_true.
          ENDIF.
        ENDLOOP.
      WHEN `EXISTS`.
        " Exists(set1, set2) relates members, with a measure group it reads facts
        result-mark = COND #( WHEN lines( node->args ) = 2 THEN args_mark ELSE c_mark-computed ).
      WHEN `NONEMPTY`.
        " NonEmpty(set [, set]) is the set's tuples whose groups with the second set's tuples have facts
        result-mark = relational( args_mark ).
      WHEN `FILTER`.
        " a condition SQL answers: the set's groups that meet it (RolapNativeFilter)
        result-mark = COND #( WHEN lines( node->args ) = 2 AND filter_condition( node->args[ 2 ] ) IS NOT INITIAL
                              THEN relational( mark( node->args[ 1 ] )-mark ) ELSE c_mark-computed ).
      WHEN `NONEMPTYCROSSJOIN`.
        result-mark = relational( args_mark ).
      WHEN `TOPCOUNT` OR `BOTTOMCOUNT`.
        result-mark = COND #( WHEN is_native_top_count( node ) = abap_true
                              THEN relational( mark( node->args[ 1 ] )-mark ) ELSE c_mark-computed ).
      WHEN `ORDER`.
        result-mark = COND #( WHEN is_native_order( node ) = abap_true
                              THEN relational( mark( node->args[ 1 ] )-mark ) ELSE c_mark-computed ).
      WHEN `VISUALTOTALS`.
        " visual total members are calculated
        result-mark = c_mark-computed.
        result-calculated = abap_true.
      WHEN OTHERS.
        " operators, value functions (aggregates, IIf, CASE, string functions, ...) and sets that depend on values
        " (Filter of another condition, Generate, Existing, ...)
        result-mark = c_mark-computed.
    ENDCASE.
  ENDMETHOD.

  METHOD relational.
    result = COND #( WHEN args_mark = c_mark-computed OR plain_context = abap_false THEN c_mark-computed
                     ELSE c_mark-relational ).
  ENDMETHOD.

  METHOD is_native_top_count.
    IF lines( node->args ) <> 3.
      RETURN.
    ENDIF.
    result = xsdbool( mark( node->args[ 2 ] )-mark = c_mark-static AND is_stored_measure( node->args[ 3 ] ) = abap_true ).
  ENDMETHOD.

  METHOD is_native_order.
    " the keys from the second argument, each followed by its direction
    DATA(index) = 2.
    WHILE index <= lines( node->args ).
      DATA(key) = node->args[ index ].
      DATA(direction) = VALUE ty_node( node->args[ index + 1 ] OPTIONAL ).
      IF direction IS NOT BOUND OR direction->kind <> zzxxmla1_cl_mdx_node=>c_kind-literal
         OR ( to_upper( direction->value ) <> `BASC` AND to_upper( direction->value ) <> `BDESC` ).
        RETURN.
      ENDIF.
      IF is_stored_measure( key ) = abap_false
         AND NOT ( key->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call AND to_upper( key->name ) = `ORDERKEY`
                   AND mark( key )-mark = c_mark-static ).
        RETURN.
      ENDIF.
      index = index + 2.
    ENDWHILE.
    result = abap_true.
  ENDMETHOD.

  METHOD is_stored_measure.
    result = xsdbool( node->kind = zzxxmla1_cl_mdx_node=>c_kind-member
                      AND node->element-member-hier_id = zzxxmla1_cl_mdx_schema_reader=>c_measures
                      AND node->element-member-calculated = abap_false ).
  ENDMETHOD.

  METHOD filter_condition.
    condition_node( EXPORTING node = node logical = abap_true
                    IMPORTING found = DATA(found) empty = DATA(empty)
                    CHANGING  condition = result ).
    IF found = abap_false OR empty = abap_false.
      CLEAR result.
    ENDIF.
  ENDMETHOD.

  METHOD condition_node.
    CLEAR: found, empty.
    IF node->kind = zzxxmla1_cl_mdx_node=>c_kind-literal.
      " NumberSqlCompiler: a decimal number (digits and a point; a sign is an operator)
      IF logical = abap_false AND node->category = zzxxmla1_cl_mdx_node=>c_category-numeric
         AND node->value CO `0123456789.` AND node->value <> `.` AND count( val = node->value sub = `.` ) <= 1.
        APPEND VALUE #( operator = zzxxmla1_cl_mdx_facts=>c_condition-number number = node->value ) TO condition.
        found = abap_true.
      ENDIF.
      RETURN.
    ENDIF.
    IF node->kind = zzxxmla1_cl_mdx_node=>c_kind-member.
      " StoredMeasureSqlCompiler
      IF logical = abap_false AND node->element-member-hier_id = zzxxmla1_cl_mdx_schema_reader=>c_measures
         AND node->element-member-calculated = abap_false AND node->element-member-measure_index > 0.
        APPEND VALUE #( operator = zzxxmla1_cl_mdx_facts=>c_condition-measure
                        measure  = node->element-member-measure_index ) TO condition.
        found = abap_true.
        empty = abap_true.
      ENDIF.
      RETURN.
    ENDIF.
    IF node->kind <> zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
      RETURN.
    ENDIF.
    DATA(name) = to_upper( node->fun_def-name ).
    IF node->fun_def-implementation = `ParenthesesFunDef` AND lines( node->args ) = 1.
      condition_node( EXPORTING node = node->args[ 1 ] logical = logical
                      IMPORTING found = found empty = empty
                      CHANGING  condition = condition ).
      RETURN.
    ENDIF.
    IF node->fun_def-syntax <> zzxxmla1_cl_mdx_node=>c_syntax-infix OR lines( node->args ) <> 2.
      RETURN.
    ENDIF.
    " the arguments' categories: numbers, or conditions of AND and OR
    DATA(arguments_logical) = abap_false.
    IF logical = abap_true AND ( name = `AND` OR name = `OR` ).
      arguments_logical = abap_true.
    ELSEIF NOT ( ( logical = abap_true AND ( name = `<` OR name = `<=` OR name = `>` OR name = `>=` OR name = `=`
                                            OR name = `<>` ) )
                 OR ( logical = abap_false AND ( name = `+` OR name = `-` OR name = `*` ) ) ).
      RETURN.
    ENDIF.
    DATA(category) = COND i( WHEN arguments_logical = abap_true THEN zzxxmla1_cl_mdx_type=>c_category-logical
                             ELSE zzxxmla1_cl_mdx_type=>c_category-numeric ).
    IF parameter_category( node = node index = 1 ) <> category OR parameter_category( node = node index = 2 ) <> category.
      RETURN.
    ENDIF.
    " the operation before its arguments
    APPEND VALUE #( operator = name ) TO condition.
    DATA(index) = lines( condition ).
    DATA(empties) = VALUE zzxxmla1_cl_mdx_facts=>ty_t_index( ).
    DATA(children) = VALUE zzxxmla1_cl_mdx_facts=>ty_t_index( ).
    LOOP AT node->args INTO DATA(arg).
      APPEND lines( condition ) + 1 TO children.
      condition_node( EXPORTING node = arg logical = arguments_logical
                      IMPORTING found = DATA(arg_found) empty = DATA(arg_empty)
                      CHANGING  condition = condition ).
      IF arg_found = abap_false.
        RETURN.
      ENDIF.
      IF arg_empty = abap_true.
        APPEND sy-tabix TO empties.
      ENDIF.
    ENDLOOP.
    condition[ index ]-children = children.
    found = abap_true.
    " false or empty without facts: OR, + and - with both sides so, AND, * and the comparisons with one
    empty = xsdbool( lines( empties ) = 2
                     OR ( lines( empties ) = 1 AND name <> `OR` AND name <> `+` AND name <> `-` ) ).
  ENDMETHOD.

  METHOD has_calculated.
    IF hierarchy = zzxxmla1_cl_mdx_type=>c_none.
      result = xsdbool( calculated_hierarchies IS NOT INITIAL ).
    ELSE.
      result = xsdbool( line_exists( calculated_hierarchies[ table_line = hierarchy ] ) ).
    ENDIF.
  ENDMETHOD.

  METHOD parameter_category.
    " the signature that matched; a MultiResolver's parameter categories are the arguments' own
    DATA(categories) = COND zzxxmla1_cl_mdx_funtable=>ty_t_category( WHEN node->fun_def-signature_categories IS NOT INITIAL
                               THEN node->fun_def-signature_categories
                               ELSE node->fun_def-parameter_categories ).
    result = VALUE i( categories[ index ] OPTIONAL ) MOD 32.
  ENDMETHOD.

  METHOD is_scalar_category.
    result = xsdbool( category = zzxxmla1_cl_mdx_type=>c_category-numeric
                      OR category = zzxxmla1_cl_mdx_type=>c_category-integer
                      OR category = zzxxmla1_cl_mdx_type=>c_category-string
                      OR category = zzxxmla1_cl_mdx_type=>c_category-logical
                      OR category = zzxxmla1_cl_mdx_type=>c_category-value
                      OR category = zzxxmla1_cl_mdx_type=>c_category-datetime ).
  ENDMETHOD.

  METHOD cells_shown.
    IF cell_properties IS INITIAL.
      result = abap_true.
      RETURN.
    ENDIF.
    LOOP AT cell_properties INTO DATA(cell_property).
      SPLIT cell_property AT `.` INTO cell_property DATA(rest) ##NEEDED.
      IF cell_property CP `[*]`.
        cell_property = substring( val = cell_property off = 1 len = strlen( cell_property ) - 2 ).
      ENDIF.
      cell_property = to_upper( cell_property ).
      IF cell_property = `VALUE` OR cell_property = `FORMATTED_VALUE` OR cell_property = `FORMAT_STRING`.
        result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD higher.
    result = COND #( WHEN rank( mark2 ) > rank( mark1 ) THEN mark2 ELSE mark1 ).
  ENDMETHOD.

  METHOD rank.
    result = SWITCH #( mark WHEN c_mark-static THEN 1
                            WHEN c_mark-relational THEN 2
                            WHEN c_mark-computed THEN 3
                            ELSE 0 ).
  ENDMETHOD.

ENDCLASS.
