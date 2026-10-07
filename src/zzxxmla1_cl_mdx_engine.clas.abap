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
"! Executes a parsed MDX query against a cube of the model, as RolapResult does. The query is first resolved
"! by ZZXXMLA1_CL_MDX_VALIDATOR (Query.resolve). The engine then evaluates the resolved expressions in an
"! evaluation context (ZZXXMLA1_CL_MDX_EVALUATOR): the slicer in the default context, the axes in the context of the
"! slicer, and every cell in the context of the slicer and one tuple of each axis. Expressions are evaluated as
"! The reference's compiled expressions (calc) do: every argument as the category its function's signature declares
"! (member, tuple, set, hierarchy, level, number), with the reference's implicit conversions (a dimension is its default
"! hierarchy, a hierarchy its current member, a member where a value is wanted the cell of the context with that member).
"! Functions so far: {}, (), CrossJoin, *, NonEmptyCrossJoin, Members, AllMembers (with calculated members), Children,
"! CurrentMember, DefaultMember, Hierarchize, DrilldownLevelTop, Order (Sorter's comparators), Cast, Aggregate, the set
"! functions Union, Except, Intersect, Head, Tail, Distinct, Item, SetToStr, the aggregates Count, Sum, Avg, Min, Max,
"! Rank, the member functions (Parent, FirstChild, LastChild, FirstSibling, LastSibling, NextMember, PrevMember, Lag,
"! Lead, Siblings, Ancestor, Ancestors, Ascendants, Cousin, ParallelPeriod, PeriodsToDate, Level, Hierarchy,
"! Dimension, Name, UniqueName, Caption, Ordinal, OrderKey), IN, MATCHES, IS, IS NULL, IS EMPTY, Existing, Exists,
"! VisualTotals, CurrentDateMember, Parameter, DrilldownLevel, DrilldownMember, AddCalculatedMembers, CalculatedChild,
"! LastNonEmpty, Properties, Format, Mod, CInt, CoalesceEmpty, CASE and the operators + - * / (in Java's double
"! arithmetic). A crossjoin larger than result_limit fails before it is built (result.limit). A
"! function without a member to return gives the null member of the hierarchy (RolapHierarchy.getNullMember): its cells
"! are null, and {} leaves out the tuples with a null member (SetFunDef). An evaluation error (ZZXXMLA1_CX_MDX_EVALUATION) is the value of its
"! cell only. NON EMPTY removes the positions of an axis whose cells are empty. The engine is the evaluator's Calc
"! (ZZXXMLA1_IF_MDX_CALC): it evaluates the formulas of calculated members and their format expressions. A cell's value
"! is written as XMLA writes it (a double as Double.toString) and formatted with the format string of its context.
"! A hierarchy without All member (unless its members are on the slicer or an axis) makes the slicer and the axes be
"! evaluated once per root member of it, and the results merged (RolapResult: loadSpecialMembers, evalExecute).
"! A named set (WITH SET) is evaluated once per query, the first time it is used, in the context of the slicer
"! (RolapNamedSetEvaluator, RolapResult.evaluateExp); an alias (AS) each time its AS is evaluated. A named set knows the
"! position of the tuple being iterated (Current, CurrentOrdinal) in Generate, Filter and Order.
CLASS zzxxmla1_cl_mdx_engine DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zzxxmla1_if_mdx_calc.
    INTERFACES zzxxmla1_if_mdx_roll_up.
    TYPES:
      ty_member   TYPE zzxxmla1_cl_mdx_schema_reader=>ty_member,
      ty_t_member TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY,
      ty_tuple    TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY,
      ty_t_tuple  TYPE STANDARD TABLE OF ty_tuple WITH EMPTY KEY.
    TYPES:
      "! The value of a dimension property of a member of an axis; a property without value has no entry
      BEGIN OF ty_property_value,
        member TYPE string,
        name   TYPE string,
        value  TYPE string,
      END OF ty_property_value,
      ty_t_property_value TYPE HASHED TABLE OF ty_property_value WITH UNIQUE KEY member name.
    TYPES:
      "! A member property of a level in the DIMENSION PROPERTIES of an axis (Olap4jProperty): written for the
      "! members of its level's hierarchy only, with the XML schema type of its datatype
      BEGIN OF ty_level_property,
        name      TYPE string,
        hierarchy TYPE string,   " unique name of the hierarchy of the level
        xsd_type  TYPE string,
      END OF ty_level_property,
      ty_t_level_property TYPE STANDARD TABLE OF ty_level_property WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_axis,
        name        TYPE string,
        tuples      TYPE ty_t_tuple,
        hierarchies TYPE string_table,  " the unique names of the hierarchies of the axis' set type
        "! the DIMENSION PROPERTIES of the axis (olap4j's standard member properties and properties of levels, in
        "! query order) and their values for the members of the axis; DISPLAY_INFO is the member's display_info in its
        "! tuple
        properties       TYPE string_table,
        values           TYPE ty_t_property_value,
        level_properties TYPE ty_t_level_property,  " the properties of levels among them
      END OF ty_axis,
      ty_t_axis TYPE STANDARD TABLE OF ty_axis WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_cell,
        ordinal    TYPE i,
        empty      TYPE abap_bool,
        value      TYPE string,
        value_type TYPE string,   " the xsi:type of the Value: xsd:double, xsd:string, ...
        formatted  TYPE string,
        format_string TYPE string, " only if the query asks for the cell property FORMAT_STRING
      END OF ty_cell,
      ty_t_cell TYPE STANDARD TABLE OF ty_cell WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_result,
        cube_name   TYPE string,
        last_update TYPE timestamp,
        axes        TYPE ty_t_axis,
        has_slicer  TYPE abap_bool,
        slicer      TYPE ty_t_tuple,  " the tuples of the slicer; several for a compound slicer
        cells       TYPE ty_t_cell,
        "! the CELL PROPERTIES of the query, upper case; VALUE and FORMATTED_VALUE if it names none
        cell_properties TYPE string_table,
      END OF ty_result.

    "! The largest crossjoin a query may build (result.limit, Util.checkCJResultLimit); 0: no limit. The
    "! sizes are checked before the crossjoin is built, so a query that would use up the memory of the instance fails
    "! with "Size of CrossJoin result (n) exceeded limit (m)" instead.
    CLASS-DATA result_limit TYPE i VALUE 1000000.

    "! @parameter catalog | the catalog (InfoArea) the query runs in; empty: any
    METHODS constructor
      IMPORTING catalog TYPE string.
    METHODS execute
      IMPORTING query         TYPE zzxxmla1_cl_mdx_parser=>ty_query
      RETURNING VALUE(result) TYPE ty_result
      RAISING   zzxxmla1_cx_xmla.
    "! Executes a DRILLTHROUGH statement (MondrianOlap4jStatement.executeQuery2): its query, then the fact rows of the
    "! first cell (RolapCell.drillThroughInternal with an extended context): every level column of the cube's
    "! hierarchies and the cell's measure, the columns constrained to the cell's members, at most MAXROWS rows after
    "! the first FIRSTROWSET; with a RETURN clause only its levels and measures.
    METHODS drill_through
      IMPORTING statement     TYPE zzxxmla1_cl_mdx_parser=>ty_statement
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_facts=>ty_drill_through
      RAISING   zzxxmla1_cx_xmla.

  PRIVATE SECTION.
    "! the context of the slicer that every cell of the executed query has (a compound slicer's placeholders)
    DATA cell_slicer TYPE ty_t_member.
    "! RolapCell.replaceTrivialCalcMember: a calculated member defined as another member, or as the Aggregate of a set
    "! of one member, is that member.
    METHODS trivial_member
      IMPORTING member        TYPE ty_member
      RETURNING VALUE(result) TYPE ty_member.
    "! The RETURN clause of a drill-through (DrillThrough.resolveReturnList, addNonConstrainingColumns): a level, the
    "! first level of a hierarchy or of a dimension's default hierarchy, or a stored measure.
    METHODS drill_through_items
      IMPORTING return_list   TYPE zzxxmla1_cl_mdx_node=>ty_t_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_facts=>ty_t_drill_item
      RAISING   zzxxmla1_cx_xmla.
    "! The fault of a failed drill-through (XmlaHandler.executeDrillThroughQuery: HSB_DRILL_THROUGH_SQL).
    CLASS-METHODS drill_through_error
      IMPORTING message TYPE string
      RAISING   zzxxmla1_cx_xmla.
    TYPES ty_node TYPE REF TO zzxxmla1_cl_mdx_node.
    TYPES ty_evaluator TYPE REF TO zzxxmla1_if_mdx_evaluator.
    CONSTANTS:
      BEGIN OF c_category,
        dimension TYPE i VALUE 2,
        hierarchy TYPE i VALUE 3,
        level   TYPE i VALUE 4,
        logical TYPE i VALUE 5,
        member  TYPE i VALUE 6,
        string  TYPE i VALUE 9,
        numeric  TYPE i VALUE 7,
        tuple    TYPE i VALUE 10,
        value    TYPE i VALUE 13,
        integer  TYPE i VALUE 15,
        datetime TYPE i VALUE 18,
      END OF c_category.

    TYPES ty_t_member_lists TYPE STANDARD TABLE OF ty_t_member WITH EMPTY KEY.

    DATA catalog       TYPE string.
    DATA schema_reader TYPE REF TO zzxxmla1_cl_mdx_schema_reader.
    "! the root evaluator of the query being executed (RolapEvaluatorRoot): it keeps the calculations of their own of
    "! the members made while the query runs (compound slicer placeholders, visual totals)
    DATA root_evaluator TYPE REF TO zzxxmla1_cl_mdx_evaluator.
    TYPES:
      "! The value of a named set (RolapNamedSetEvaluator): its tuples and the position of the current one.
      BEGIN OF ty_named_set_value,
        key     TYPE string,
        tuples  TYPE ty_t_tuple,
        ordinal TYPE i,
      END OF ty_named_set_value.
    DATA named_set_values TYPE HASHED TABLE OF ty_named_set_value WITH UNIQUE KEY key.
    "! the context of RolapResult.slicerEvaluator: the default members, after the slicer is determined with its members
    DATA slicer_evaluator_context TYPE ty_t_member.
    "! the visual total members made so far (their calc_name)
    DATA visual_total_count TYPE i.
    "! An argument of a native crossjoin (CrossJoinArg): the members of one level, either a level's members below a
    "! member or all of them (DescendantsCrossJoinArg), or a list of members (MemberListCrossJoinArg).
    TYPES:
      BEGIN OF ty_cj_arg,
        hierarchy    TYPE i,
        level        TYPE i,
        members      TYPE ty_t_member,
        member_list  TYPE abap_bool,
        has_all      TYPE abap_bool,
        has_calc     TYPE abap_bool,
        has_non_calc TYPE abap_bool,
      END OF ty_cj_arg,
      ty_t_cj_arg TYPE STANDARD TABLE OF ty_cj_arg WITH EMPTY KEY,
      "! the alternative arguments of an operand (one per level of its members), or the arguments of a variant
      ty_t_cj_args TYPE STANDARD TABLE OF ty_t_cj_arg WITH EMPTY KEY.
    "! the facts of the query, for the native crossjoin
    DATA fact_reader TYPE REF TO zzxxmla1_cl_mdx_facts.
    "! Query.getMeasuresMembers: the measures the query names, the second set of a NON EMPTY axis' NonEmpty
    DATA query_measures TYPE ty_t_member.
    TYPES ty_path_set TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    TYPES:
      "! the paths of a level's members with facts in a context, by the filters of the context and the level
      BEGIN OF ty_context_paths,
        key   TYPE string,
        paths TYPE ty_path_set,
      END OF ty_context_paths.
    DATA context_paths_cache TYPE HASHED TABLE OF ty_context_paths WITH UNIQUE KEY key.
    "! LevelPreCacheThreshold: a level of no more members is read whole, also under a non-empty evaluator
    CONSTANTS c_level_pre_cache_threshold TYPE i VALUE 300.

    "! RolapResult.loadSpecialMembers: per hierarchy whose current member is not calculated, not the All member and not
    "! a measure, and that has no All member, its root members (the nonAllMembers). A TimeDimension is skipped.
    METHODS load_special_members
      IMPORTING evaluator     TYPE ty_evaluator
      RETURNING VALUE(result) TYPE ty_t_member_lists.
    "! RolapResult.replaceNonAllMembers: the members of a hierarchy among the given ones replace its list.
    "! @parameter result | a list was replaced
    METHODS replace_non_all_members
      IMPORTING members       TYPE ty_t_member
      CHANGING  lists         TYPE ty_t_member_lists
      RETURNING VALUE(result) TYPE abap_bool.
    "! AxisMemberList.mergeMember for an axis: the top ancestors of the members of the tuples, each once, without
    "! measures, calculated members and All members.
    METHODS top_members
      IMPORTING tuples        TYPE ty_t_tuple
      RETURNING VALUE(result) TYPE ty_t_member.
    "! RolapResult.evalExecute: the axis executed with each member of the lists (from the last list) in the context,
    "! the results merged.
    METHODS eval_execute
      IMPORTING evaluator     TYPE ty_evaluator
                lists         TYPE ty_t_member_lists
                index         TYPE i
                expression    TYPE ty_node
                non_empty     TYPE abap_bool
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! RolapResult.mergeAxes: the tuples of both, each once; hierarchized if both contribute and the axis is not
    "! ordered.
    METHODS merge_axes
      IMPORTING axis1         TYPE ty_t_tuple
                axis2         TYPE ty_t_tuple
                ordered       TYPE abap_bool
      RETURNING VALUE(result) TYPE ty_t_tuple.
    "! RolapResult.CalculatedMeasureVisitor: the dimension of the last dimension, hierarchy or member the expression
    "! names (depth first); -1 if none.
    METHODS last_dimension
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE i.

    "! SetType.getHierarchies: the unique names of the hierarchies of a set's members or tuples (the axis metadata).
    METHODS type_hierarchies
      IMPORTING type          TYPE REF TO zzxxmla1_cl_mdx_type
      RETURNING VALUE(result) TYPE string_table.
    "! An axis or the slicer (RolapResult.executeAxis): the set in the evaluator's context, with the axis' NON EMPTY.
    "! Query.compile makes the set of a NON EMPTY axis NonEmpty(set, {the query's measures}).
    METHODS execute_axis
      IMPORTING evaluator     TYPE ty_evaluator
                expression    TYPE ty_node
                non_empty     TYPE abap_bool
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! NonEmpty(set, {the query's measures}) (NonEmptyFunDef, the set evaluated already): the tuples whose cell is not
    "! empty with one of the measures in the context; with the measure of the context if the query names none.
    METHODS non_empty_axis
      IMPORTING evaluator     TYPE ty_evaluator
                tuples        TYPE ty_t_tuple
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! FunUtil.getNonEmptyLevelMembers (RolapSchemaReader.getLevelMembers with the evaluator): under a non-empty
    "! evaluator the members of a level of more than LevelPreCacheThreshold members are read with a
    "! SqlContextConstraint (context_members); otherwise all of them. The reference constrains them by the other axes
    "! too (buildConstraintFromAllAxes); NON EMPTY removes the same positions afterwards.
    METHODS non_empty_level_members
      IMPORTING evaluator     TYPE ty_evaluator
                level         TYPE i
      RETURNING VALUE(result) TYPE ty_t_member.
    "! FunUtil.getNonEmptyMemberChildren (RolapSchemaReader.getMemberChildren with the evaluator): under a non-empty
    "! evaluator the children with facts in the context with the member set (SqlContextConstraint.addMemberConstraint).
    METHODS non_empty_children
      IMPORTING evaluator     TYPE ty_evaluator
                member        TYPE ty_member
      RETURNING VALUE(result) TYPE ty_t_member.
    "! SqlContextConstraint: under a non-empty evaluator the members (stored ones of one hierarchy) that have facts in
    "! the context, read once per level and context with ZZXXMLA1_CL_MDX_FACTS=>non_empty_paths. The context
    "! (makeContextConstraintSet) is the stored members that are not their hierarchy's default member; one of the
    "! members' hierarchy keeps only the members on its path. All members are kept where the reference does not use the
    "! constraint (isValidContext: a calculated measure's member in conflict) or where it is not ported (a calculated
    "! member or the null member in the context: the reference expands an Aggregate, makes no request for the null
    "! member).
    METHODS context_members
      IMPORTING evaluator     TYPE ty_evaluator
                members       TYPE ty_t_member
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The paths of the members of the hierarchy's level with facts with the filters (kept for the query).
    METHODS context_paths
      IMPORTING filters       TYPE zzxxmla1_cl_mdx_facts=>ty_t_filter
                hierarchy     TYPE i
                key_level     TYPE i
      RETURNING VALUE(result) TYPE ty_path_set.
    "! One path is the other or begins with it: the members are on one line of ancestors.
    CLASS-METHODS on_one_path
      IMPORTING path1         TYPE string
                path2         TYPE string
      RETURNING VALUE(result) TYPE abap_bool.
    "! The cells (RolapResult.executeStripe): each tuple of the axis at the index in turn is set in the context, and
    "! the axes before it are run inside; at index 0 the slicer is set and the cell computed. The first axis runs fastest.
    METHODS execute_stripe
      IMPORTING evaluator  TYPE ty_evaluator
                axes       TYPE ty_t_axis
                slicer     TYPE ty_tuple
                axis_index TYPE i
      CHANGING  cells      TYPE ty_t_cell
      RAISING   zzxxmla1_cx_xmla.
    "! The cell of the evaluator's context as text: the value as XMLA writes it (XmlaHandler.ValueInfo), formatted with
    "! the format string of the context.
    METHODS compute_cell
      IMPORTING evaluator     TYPE ty_evaluator
      RETURNING VALUE(result) TYPE ty_cell
      RAISING   zzxxmla1_cx_xmla.
    "! NON EMPTY (RolapConnection.NonEmptyResult): removes the positions of the axis whose cells are all empty, and their
    "! cells.
    METHODS remove_empty_positions
      IMPORTING position TYPE i
      CHANGING  result   TYPE ty_result.
    "! A set expression (compileList): the tuples of a resolved expression of set type, or of a member or tuple.
    METHODS evaluate_set
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! A member expression (compileMember): a member, a hierarchy's or dimension's current member, a call.
    METHODS evaluate_member
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_member
      RAISING   zzxxmla1_cx_xmla.
    "! A tuple expression (compileTuple): a tuple of members, or one member.
    METHODS evaluate_tuple
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! A hierarchy expression (compileHierarchy): a hierarchy, the default hierarchy of a dimension, the hierarchy of a
    "! member or level.
    METHODS evaluate_hierarchy
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE i
      RAISING   zzxxmla1_cx_xmla.
    "! A level expression (compileLevel): a level, or &lt;Hierarchy&gt;.Levels(ordinal or name).
    METHODS evaluate_level
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE i
      RAISING   zzxxmla1_cx_xmla.
    "! A scalar expression (compileScalar): a literal, the cell of the context with a member or tuple set
    "! (MemberValueCalc, TupleValueCalc), or a call of a scalar function.
    METHODS evaluate_value
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_xmla.
    "! A call of a scalar function (the operators + - * / and unary -).
    METHODS evaluate_scalar_call
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_xmla.
    "! A numeric expression (compileDouble): a double or null.
    METHODS evaluate_double
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_xmla.
    "! A string expression (compileString): a string or null.
    METHODS evaluate_string
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_xmla.
    "! A logical expression (compileBoolean); null is false (BooleanNull).
    METHODS evaluate_boolean
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE abap_bool
      RAISING   zzxxmla1_cx_xmla.
    "! The comparisons = <> < <= > >= of two numbers or two strings: false if one is null (or NaN).
    METHODS compare
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE abap_bool
      RAISING   zzxxmla1_cx_xmla.
    CLASS-METHODS logical
      IMPORTING value         TYPE abap_bool
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value.
    "! A numeric expression as a number (compileInteger / compileDouble); null is 0.
    METHODS evaluate_number
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE f
      RAISING   zzxxmla1_cx_xmla.
    "! A double result, or the special value Java's double arithmetic gives for a division by zero.
    CLASS-METHODS divide
      IMPORTING dividend      TYPE f
                divisor       TYPE f
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value.
    "! FunUtil.hierarchyMembers / levelMembers with calculated members: each level's members, then its calculated
    "! members.
    METHODS members_with_calculated
      IMPORTING evaluator     TYPE ty_evaluator
                levels        TYPE zzxxmla1_cl_mdx_schema_reader=>ty_t_id
      RETURNING VALUE(result) TYPE ty_t_tuple.
    "! An argument of * or () as a set: a set, or the member or tuple as a set of one tuple.
    METHODS evaluate_arg_as_set
      IMPORTING evaluator     TYPE ty_evaluator
                call          TYPE ty_node
                index         TYPE i
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! The key of a function definition: name, syntax and the categories of the matching signature, e.g.
    "! MEMBERS|Property|3.
    CLASS-METHODS key_of
      IMPORTING node          TYPE ty_node
      RETURNING VALUE(result) TYPE string.
    METHODS not_implemented
      IMPORTING node TYPE ty_node
      RAISING   zzxxmla1_cx_xmla.
    METHODS cross_join
      IMPORTING left          TYPE ty_t_tuple
                right         TYPE ty_t_tuple
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! Util.checkCJResultLimit: the query fails if the size exceeds the result limit, or Integer.MAX_VALUE.
    CLASS-METHODS check_result_limit
      IMPORTING size TYPE decfloat34
      RAISING   zzxxmla1_cx_xmla.
    "! A number as Java's MessageFormat {0,number} writes it (en_US): groups of three digits separated by commas.
    CLASS-METHODS group_digits
      IMPORTING number        TYPE decfloat34
      RETURNING VALUE(result) TYPE string.
    "! NonEmptyCrossJoin (CrossJoinFunDef.nonEmptyList): the tuples whose cell in the context is not empty.
    METHODS non_empty_list
      IMPORTING evaluator     TYPE ty_evaluator
                tuples        TYPE ty_t_tuple
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! Hierarchize (Sorter.hierarchizeTupleList, FunUtil.compareHierarchically): an ancestor before its descendants,
    "! siblings by Sorter.compareSiblingMembers; tuples by their members in turn. A stable sort.
    METHODS hierarchize
      IMPORTING tuples        TYPE ty_t_tuple
      RETURNING VALUE(result) TYPE ty_t_tuple.
    "! The key of a member for hierarchize: its own ordinal (the pre-order of the stored members), or with calculated
    "! members in the set the path from the root, a stored member as 0 and its ordinal, a calculated one as 1, its
    "! ordinal and its name (after its stored siblings and their descendants).
    METHODS hierarchize_key
      IMPORTING member        TYPE ty_member
                path          TYPE abap_bool
      RETURNING VALUE(result) TYPE string.
    METHODS drill_down_level_top
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    TYPES:
      "! A key of Order (SortKeySpec): the expression (unbound: the cell of the context, ValueCalc) and the direction
      "! (Sorter.Flag: descending, break hierarchy).
      BEGIN OF ty_sort_key,
        expression TYPE ty_node,
        descending TYPE abap_bool,
        brk        TYPE abap_bool,
      END OF ty_sort_key,
      ty_t_sort_key TYPE STANDARD TABLE OF ty_sort_key WITH EMPTY KEY.
    TYPES:
      "! A value of a key for a member or tuple (the comparators' value maps), per run of Order.
      BEGIN OF ty_sort_value,
        run   TYPE i,
        key   TYPE i,
        name  TYPE string,
        value TYPE zzxxmla1_cl_mdx_evaluator=>ty_value,
      END OF ty_sort_value.
    DATA sort_values TYPE HASHED TABLE OF ty_sort_value WITH UNIQUE KEY run key name.
    DATA sort_run    TYPE i.
    "! Filter(set, condition) (FilterFunDef): the tuples of the set, in order, for which the condition is true with the
    "! tuple as the context; not empty-filtered.
    METHODS filter
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! TopCount / BottomCount(set, count [, value]) (TopBottomCountFunDef): without a value the first / last count
    "! tuples of the set; with one the first count tuples of a stable sort by the value, descending / ascending, that
    "! breaks the hierarchy (Sorter.partiallySortMembers, partiallySortTuples).
    METHODS top_bottom_count
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
                top           TYPE abap_bool
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! member : member (RangeFunDef, FunUtil.memberRange): the members of their level from the one to the other in
    "! hierarchy order, in either order of the arguments.
    METHODS range
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! Descendants(member | set [, level | depth | empty [, flag]]) (DescendantsFunDef): of a set as
    "! Generate(set, Descendants(hierarchy.CurrentMember, ...)), the descendants of each member once.
    METHODS descendants
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! The descendants of one member (DescendantsFunDef.compileCall for a member), in hierarchy order.
    METHODS descendants_of_member
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
                member        TYPE ty_member
      RETURNING VALUE(result) TYPE ty_t_member
      RAISING   zzxxmla1_cx_xmla.
    "! DescendantsFunDef.descendantsByDepth: the generations before, at and after the depth (0 the member itself).
    METHODS descendants_by_depth
      IMPORTING evaluator     TYPE ty_evaluator
                member        TYPE ty_member
                depth_limit   TYPE i
                before        TYPE abap_bool
                self          TYPE abap_bool
                after         TYPE abap_bool
      RETURNING VALUE(result) TYPE ty_t_member.
    "! DescendantsFunDef.descendantsLeavesByDepth: the members without a child level down to the depth (-1: all).
    METHODS descendants_leaves_by_depth
      IMPORTING member        TYPE ty_member
                depth_limit   TYPE i
      RETURNING VALUE(result) TYPE ty_t_member.
    "! DescendantsFunDef.descendantsByLevel: the members above, at and below the level's depth; LEAVES: the members at
    "! the depth and those above it without children.
    METHODS descendants_by_level
      IMPORTING evaluator     TYPE ty_evaluator
                ancestor      TYPE ty_member
                level         TYPE i
                before        TYPE abap_bool
                self          TYPE abap_bool
                after         TYPE abap_bool
                leaves        TYPE abap_bool
      RETURNING VALUE(result) TYPE ty_t_member.
    "! RolapSchemaReader.isDrillable: the level of the member has a child level.
    METHODS is_drillable
      IMPORTING member        TYPE ty_member
      RETURNING VALUE(result) TYPE abap_bool.
    "! The depth of the member's level (the (All) level 0); calculated members as their level.
    METHODS depth_of
      IMPORTING member        TYPE ty_member
      RETURNING VALUE(result) TYPE i.
    "! Order(set, key [, ASC | DESC | BASC | BDESC] ...) (OrderFunDef): the tuples sorted by the keys in turn (a stable
    "! sort, as Java's), not empty-filtered.
    METHODS order
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! A stable merge sort of the tuples by the keys.
    METHODS sort_tuples
      IMPORTING evaluator TYPE ty_evaluator
                keys      TYPE ty_t_sort_key
                run       TYPE i
      CHANGING  tuples    TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! The comparator chain (ComparatorChain): the first key whose comparison is not 0 decides.
    METHODS compare_by_keys
      IMPORTING evaluator     TYPE ty_evaluator
                keys          TYPE ty_t_sort_key
                run           TYPE i
                tuple1        TYPE ty_tuple
                tuple2        TYPE ty_tuple
      RETURNING VALUE(result) TYPE i
      RAISING   zzxxmla1_cx_xmla.
    "! One key: for members (Sorter.sortMembers) BreakMemberComparator or HierarchicalMemberComparator, for tuples
    "! (Sorter.sortTuples) BreakTupleComparator (reversed if descending) or HierarchicalTupleComparator.
    METHODS compare_by_key
      IMPORTING evaluator     TYPE ty_evaluator
                key           TYPE ty_sort_key
                key_index     TYPE i
                run           TYPE i
                tuple1        TYPE ty_tuple
                tuple2        TYPE ty_tuple
      RETURNING VALUE(result) TYPE i
      RAISING   zzxxmla1_cx_xmla.
    "! The value of the key with the members (a member or a tuple) as context, computed once per run (eval).
    METHODS sort_value
      IMPORTING evaluator     TYPE ty_evaluator
                key           TYPE ty_sort_key
                key_index     TYPE i
                run           TYPE i
                members       TYPE ty_tuple
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_xmla.
    "! compareHierarchicallyButSiblingsByValue: an ancestor before its descendants, siblings by value, siblings of equal
    "! value in hierarchy order. For a member (MemberComparator) only the value comparison is negated if descending,
    "! for a tuple member (HierarchicalTupleComparator) the whole result, and the value is not memorized: the context
    "! then holds the tuple's members before this one.
    METHODS compare_hierarchically
      IMPORTING evaluator     TYPE ty_evaluator
                key           TYPE ty_sort_key
                key_index     TYPE i
                run           TYPE i
                member1       TYPE ty_member
                member2       TYPE ty_member
                in_tuple      TYPE abap_bool
      RETURNING VALUE(result) TYPE i
      RAISING   zzxxmla1_cx_xmla.
    "! The value of a key in the context.
    METHODS evaluate_key
      IMPORTING evaluator     TYPE ty_evaluator
                key           TYPE ty_sort_key
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_xmla.
    "! TupleExpMemoComparator.dependentMembers: the members of the tuple whose hierarchies the key depends on.
    METHODS dependent_members
      IMPORTING key           TYPE ty_sort_key
                tuple         TYPE ty_tuple
      RETURNING VALUE(result) TYPE ty_tuple.
    "! Calc.dependsOn(hierarchy): whether the value of the expression may change if the current member of the hierarchy
    "! changes. A member, level or literal is constant; a hierarchy (its current member) depends on itself; a member or
    "! tuple evaluated as a value (MemberValueCalc, TupleValueCalc) on every hierarchy it does not set; a call on what its
    "! arguments depend on.
    "! @parameter as_value | the expression is evaluated as a scalar value
    METHODS depends_on
      IMPORTING node          TYPE ty_node
                hierarchy     TYPE i
                as_value      TYPE abap_bool
      RETURNING VALUE(result) TYPE abap_bool.
    "! Sorter.compareSiblingMembers: calculated members after the others, then by ordinal, then by key (name).
    CLASS-METHODS compare_siblings
      IMPORTING member1       TYPE ty_member
                member2       TYPE ty_member
      RETURNING VALUE(result) TYPE i.
    "! Sorter.compareValues( Object, Object ): null before anything, strings ignoring case, numbers as doubles (NaN after
    "! everything but positive infinity).
    METHODS compare_values
      IMPORTING value1        TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
                value2        TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RETURNING VALUE(result) TYPE i
      RAISING   zzxxmla1_cx_xmla.
    "! CAST(value AS type) (CastFunDef.CalcImpl): String.valueOf, Integer.parseInt / intValue, Double.valueOf /
    "! doubleValue, Boolean.valueOf / greater than 0.
    METHODS cast
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_xmla.
    "! &lt;Hierarchy&gt;.CurrentMember (HierarchyCurrentMemberFunDef): the member of the context; an error if the slicer
    "! has several members of the hierarchy (validateSlicerMembers, CurrentMemberWithCompoundSlicerAlert ERROR).
    METHODS current_member
      IMPORTING evaluator     TYPE ty_evaluator
                hierarchy     TYPE i
      RETURNING VALUE(result) TYPE ty_member
      RAISING   zzxxmla1_cx_xmla.
    "! A slicer of several tuples (RolapResult, Execute Slicer): the members that are the same in all tuples are the
    "! context (removeUnaryMembersFromTupleList), each other hierarchy of the tuples gets a placeholder
    "! (CompoundSlicerRolapMember): a calculated member of the cube with the lowest solve order (-99999,
    "! CompoundSlicerMemberSolveOrder) whose value is the cell of the context rolled up over the tuples.
    "! @parameter members | the slicer members (setSlicerContext)
    "! @parameter result | the context of the slicer: the members, then the unary members and the placeholders
    METHODS compound_slicer
      IMPORTING tuples        TYPE ty_t_tuple
                members       TYPE ty_t_member
      RETURNING VALUE(result) TYPE ty_t_member.
    "! Aggregate(set [, numeric]) (AggregateFunDef.AggregateCalc): the values of the tuples of the set rolled up with
    "! the aggregator of the measure of the context (sum; count rolls up as sum; min, max).
    METHODS aggregate
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_xmla.
    TYPES ty_t_value TYPE STANDARD TABLE OF zzxxmla1_cl_mdx_evaluator=>ty_value WITH EMPTY KEY.
    "! A tuple as the key of a set of tuples (List&lt;Member&gt;.equals): its members' unique names.
    CLASS-METHODS tuple_key
      IMPORTING tuple         TYPE ty_tuple
      RETURNING VALUE(result) TYPE string.
    "! FunUtil.getLiteralArg: the symbol at the index (the default if there is none) as one of the allowed values,
    "! compared ignoring case.
    METHODS literal_arg
      IMPORTING node          TYPE ty_node
                index         TYPE i
                default_value TYPE string
                allowed       TYPE string_table
      RETURNING VALUE(result) TYPE string
      RAISING   zzxxmla1_cx_xmla.
    "! An error of compiling a call (FunUtil.newEvalException while the query is compiled): a fault of the query.
    METHODS compile_error
      IMPORTING message TYPE string
      RAISING   zzxxmla1_cx_xmla.
    "! Union(set, set [, ALL | DISTINCT]) (UnionFunDef): the tuples of both sets, each once unless ALL.
    METHODS union
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! Except(set, set [, ALL]) and set - set (ExceptFunDef): the tuples of the first set that are not in the second,
    "! duplicates kept (ALL is not implemented by the reference either).
    METHODS except
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! Intersect(set, set [, ALL]) (IntersectFunDef): the tuples of the first set that are in the second, each once
    "! unless ALL.
    METHODS intersect
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! Head / Tail(set [, count]) (HeadTailFunDef): the first / last count tuples (default 1), non-empty off.
    METHODS head_tail
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
                head          TYPE abap_bool
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! Distinct(set) (DistinctFunDef): the tuples of the set, each once, in the order of their first occurrence.
    CLASS-METHODS distinct
      IMPORTING tuples        TYPE ty_t_tuple
      RETURNING VALUE(result) TYPE ty_t_tuple.
    "! Count(set [, EXCLUDEEMPTY | INCLUDEEMPTY]) (CountFunDef) and &lt;Set&gt;.Count: the number of tuples; EXCLUDEEMPTY
    "! counts those whose cell is not empty (FunUtil.count).
    METHODS count
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_xmla.
    "! The set of an aggregate function, non-empty off (AbstractAggregateFunDef.evaluateCurrentList).
    METHODS evaluate_current_list
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! FunUtil.evaluateSet: the values of the expression (the cell of the context if there is none) with each tuple as
    "! the context in turn, nulls left out, non-empty off; a value that is no number is Java's ClassCastException.
    METHODS evaluate_values
      IMPORTING evaluator     TYPE ty_evaluator
                tuples        TYPE ty_t_tuple
                value         TYPE ty_node OPTIONAL
      RETURNING VALUE(result) TYPE ty_t_value
      RAISING   zzxxmla1_cx_xmla.
    "! Sum / Avg / Min / Max(set [, numeric]) (SumFunDef, AvgFunDef, MinMaxFunDef): FunUtil.sumDouble, avg, min, max
    "! of the values; null if there is none.
    METHODS set_aggregate
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_xmla.
    "! FunUtil.sumDouble, avg, min, max of values (numbers) as a double in Java's arithmetic (a NaN or opposite
    "! infinities make a sum NaN; min and max compare with &lt; and &gt;, false for NaN); null if there is no value.
    "! @parameter function | sum, avg, min or max
    CLASS-METHODS fold_values
      IMPORTING values        TYPE ty_t_value
                function      TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value.
    "! Java's value1 &lt; value2 of doubles: false if one is NaN.
    CLASS-METHODS java_less
      IMPORTING value1        TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
                value2        TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RETURNING VALUE(result) TYPE abap_bool.
    "! Rank(tuple, set [, value]) (RankFunDef): without a value the 1-based position of the tuple's first occurrence in
    "! the set (0 if it is not in it); with one the 1-based position of its value among the values of the set sorted
    "! descending, equal values the same rank, a null value after all (SortedListCalc, Rank3TupleCalc).
    METHODS rank
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_xmla.
    "! SetToStr(set) (SetToStrFunDef): {member, ...} or {(member, ...), ...} of unique names.
    METHODS set_to_str
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_xmla.
    "! &lt;Set&gt;.Item(index | name [, name ...]) (SetItemFunDef): the tuple at the 0-based index, or the first whose
    "! members have the names; the set is evaluated non-empty off.
    METHODS set_item
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! &lt;Tuple&gt;.Item(index) (TupleItemFunDef): the member at the 0-based index; a member is its own item 0.
    METHODS tuple_item
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_member
      RAISING   zzxxmla1_cx_xmla.
    "! A named set (NamedSetExpr) or an alias (the named set of an AS call): its tuples, evaluated in the context of the
    "! slicer, non-empty off, if they are not known yet or the alias is evaluated anew.
    METHODS named_set_tuples
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
                anew          TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! TupleList.PositionCallback: the tuple at the index (from 1) of the set is the current one of its named set, if
    "! the set is a named set or an alias.
    METHODS set_position
      IMPORTING node         TYPE ty_node
                VALUE(index) TYPE i.
    "! &lt;Set&gt;.Current (NamedSetCurrentFunDef): the tuple at the current position of the named set.
    METHODS named_set_current
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! Generate(set1, set2 [, ALL]) (GenerateListCalcImpl): set2 with each tuple of set1 (evaluated non-empty off) as
    "! the context in turn, joined, each tuple once unless ALL.
    METHODS generate
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! Generate(set, string [, delimiter]) (GenerateStringCalcImpl): the string with each tuple as the context, joined
    "! by the delimiter (evaluated before each one but the first). Generate(set, numeric, delimiter) joins the numbers
    "! as Str writes them (GenerateFunDef.compileCall).
    METHODS generate_string
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_xmla.
    "! Vba.str: a number as Number.toString, with a leading space if it is >= 0 (not NaN); null for an empty one
    "! (JavaFunDef gives null for a null argument, StringBuilder.append writes it as null).
    CLASS-METHODS vba_str
      IMPORTING value         TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RETURNING VALUE(result) TYPE string.
    "! RolapHierarchy.getNullMember: the member #null of the hierarchy, on its first level.
    METHODS null_member
      IMPORTING hierarchy     TYPE i
      RETURNING VALUE(result) TYPE ty_member.
    "! The tuples without a null member (SetFunDef: a null or partially null tuple is left out).
    CLASS-METHODS without_null_tuples
      CHANGING tuples TYPE ty_t_tuple.
    "! Parent, FirstChild, LastChild, FirstSibling, LastSibling, NextMember, PrevMember, Lag, Lead (BuiltinFunTable,
    "! LeadLagFunDef): the member, or the null member if there is none.
    METHODS navigate
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_member
      RAISING   zzxxmla1_cx_xmla.
    "! The siblings of a member, itself included: the root members or its parent's children; none for the null member.
    METHODS siblings_of
      IMPORTING member        TYPE ty_member
      RETURNING VALUE(result) TYPE ty_t_member.
    "! SchemaReader.getLeadMember: the member n places further in its level (across parents), the null member beyond.
    METHODS lead_member
      IMPORTING member        TYPE ty_member
                n             TYPE int8
      RETURNING VALUE(result) TYPE ty_member.
    "! FunUtil.ancestor: the ancestor at the level (if any), else at the distance; the member at distance 0, the null
    "! member if there is none.
    METHODS ancestor
      IMPORTING member        TYPE ty_member
                distance      TYPE i
                level         TYPE i DEFAULT 0
      RETURNING VALUE(result) TYPE ty_member
      RAISING   zzxxmla1_cx_xmla.
    "! Ancestors(member, level | distance) (AncestorsFunDef): the ancestors at the distances 1 to the distance.
    METHODS ancestors
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! FunUtil.cousin: the member below the ancestor in the same relative position as the member.
    METHODS cousin
      IMPORTING member        TYPE ty_member
                ancestor      TYPE ty_member
      RETURNING VALUE(result) TYPE ty_member
      RAISING   zzxxmla1_cx_xmla.
    "! FunUtil.cousin2: initial if there is no such member.
    METHODS cousin2
      IMPORTING member1       TYPE ty_member
                member2       TYPE ty_member
      RETURNING VALUE(result) TYPE ty_member.
    "! The cube's time hierarchy (RolapCube.getTimeHierarchy), an error if there is none.
    METHODS time_hierarchy
      IMPORTING function_name TYPE string
      RETURNING VALUE(result) TYPE i
      RAISING   zzxxmla1_cx_xmla.
    "! ParallelPeriod([level [, lag [, member]]]) (ParallelPeriodFunDef): the cousin of the member below the ancestor's
    "! lag-th predecessor.
    METHODS parallel_period
      IMPORTING evaluator     TYPE ty_evaluator
              node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_member
      RAISING   zzxxmla1_cx_xmla.
    "! PeriodsToDate([level [, member]]) (PeriodsToDateFunDef, FunUtil.periodsToDate): the members of the member's
    "! level from the first descendant of its ancestor at the level to the member.
    METHODS periods_to_date
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! FunUtil.periodsToDate with a level and a member: the members of the member's level from the first descendant
    "! of its ancestor at the level to the member; none if the level is not above the member's.
    METHODS periods_to_date_of
      IMPORTING level         TYPE i
                member        TYPE ty_member
      RETURNING VALUE(result) TYPE ty_t_tuple.
    "! Ytd, Qtd, Mtd, Wtd([member]) (XtdFunDef): PeriodsToDate at the cube's first time level of the year, quarter, month
    "! or week type (CubeBase.getTimeLevel), of the member or the current member of that level's hierarchy.
    METHODS xtd
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! OpeningPeriod, ClosingPeriod([level [, member]]) (OpeningClosingPeriodFunDef): the first or last descendant of
    "! the member (the current member of the cube's time hierarchy without one) at the level (the level below the
    "! member's without one); the member itself on its own level, the null member above it or without descendants.
    METHODS opening_closing_period
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_member
      RAISING   zzxxmla1_cx_xmla.
    "! Subset(set, start [, count]) (SubsetFunDef): the set evaluated not non-empty, the tuples from the 0-based start,
    "! count of them or to the end; empty for a start outside the set or a count below 1.
    METHODS subset
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! A dimension expression: a dimension, or &lt;x&gt;.Dimension.
    METHODS evaluate_dimension
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE i
      RAISING   zzxxmla1_cx_xmla.
    "! NonEmptyCrossJoin (NonEmptyCrossJoinFunDef): non-empty on, the slicer members of the set's hierarchies at their All
    "! member, then natively; else the crossjoin without the empty tuples.
    METHODS non_empty_crossjoin
      IMPORTING evaluator     TYPE ty_evaluator
              node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! RolapNativeCrossJoin.createEvaluator: while the evaluator is non-empty, a crossjoin of arguments that are a
    "! level's members (Members, Children, Descendants), or members of one level, is read from the facts: the
    "! combinations with facts in the context, in hierarchy order. Else the reference server's multi-variant expansion: every
    "! operand evaluated and split by level, the variants (the first operand slowest) read one after the other, then
    "! put in the order of the operands (our fix of the reference server, scripts/patches/multivariant-order.patch).
    METHODS native_crossjoin
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      EXPORTING native        TYPE abap_bool
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! flattenCrossJoinOperands: the operands of nested two-argument crossjoins.
    METHODS crossjoin_operands
      IMPORTING node     TYPE ty_node
      CHANGING  operands TYPE zzxxmla1_cl_mdx_node=>ty_t_node.
    "! CrossJoinArgFactory.checkCrossJoinArg without evaluation: Level.Members, Member.Children, Descendants(member,
    "! level or depth) and an enumeration of members (in braces, NativizeSet or a named set).
    METHODS direct_cj_arg
      IMPORTING node   TYPE ty_node
      EXPORTING arg    TYPE ty_cj_arg
                found  TYPE abap_bool.
    "! MemberListCrossJoinArg.create: members of one level (null members left out), without the reference's bound
    "! MaxConstraints (our deviation: the bound keeps the reference's IN list small; the native read has none, it
    "! reads the level in the database and keeps the listed members, so the database expands the crossjoin).
    METHODS member_list_cj_arg
      IMPORTING members TYPE ty_t_member
      EXPORTING arg     TYPE ty_cj_arg
                found   TYPE abap_bool.
    "! The position of a member in an evaluated crossjoin operand.
    TYPES:
      BEGIN OF ty_member_position,
        unique_name TYPE string,
        position    TYPE i,
      END OF ty_member_position,
      ty_member_positions   TYPE HASHED TABLE OF ty_member_position WITH UNIQUE KEY unique_name,
      ty_t_member_positions TYPE STANDARD TABLE OF ty_member_positions WITH EMPTY KEY.
    "! resolveOperandStates: an operand's arguments: the direct one, else its members evaluated and split by level in
    "! the order of their first appearance; none if it cannot be resolved.
    "! @parameter positions | the positions of the members of an evaluated operand; none for a direct one
    METHODS operand_states
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      EXPORTING positions     TYPE ty_member_positions
      RETURNING VALUE(result) TYPE ty_t_cj_arg
      RAISING   zzxxmla1_cx_xmla.
    "! MultiVariantSetEvaluator.inOperandOrder (our fix of the reference server): the tuples of the variants in the order of the
    "! interpreted crossjoin, by each member's position in its operand; a member of a direct operand (one level) by its
    "! hierarchy order. A stable sort: tuples that compare equal keep their order.
    CLASS-METHODS in_operand_order
      IMPORTING tuples        TYPE ty_t_tuple
                orders        TYPE ty_t_member_positions
      RETURNING VALUE(result) TYPE ty_t_tuple.
    "! isVariantValid: not all arguments with the All member or empty, no calculated members, no conflict with the
    "! calculated measures, and a context without calculated members (other than measures) outside the arguments.
    "! isTrivialVariant: every argument a list of one member.
    CLASS-METHODS is_trivial_variant
      IMPORTING args          TYPE ty_t_cj_arg
      RETURNING VALUE(result) TYPE abap_bool.
    METHODS valid_cj_args
      IMPORTING evaluator     TYPE ty_evaluator
                args          TYPE ty_t_cj_arg
      RETURNING VALUE(result) TYPE abap_bool.
    "! SqlConstraintUtils.measuresConflictWithMembers: a member in a calculated measure's formula of the hierarchy of one
    "! of the members, but below none of them.
    METHODS measures_conflict
      IMPORTING members       TYPE ty_t_member
      RETURNING VALUE(result) TYPE abap_bool.
    METHODS formula_members
      IMPORTING node    TYPE ty_node
      CHANGING  members TYPE ty_t_member.
    "! SetEvaluator: the combinations of the arguments' members with facts in the context (the arguments' hierarchies
    "! at their All member), ordered by the hierarchy order of the first argument, then the second, ...
    METHODS read_native_tuples
      IMPORTING evaluator     TYPE ty_evaluator
                args          TYPE ty_t_cj_arg
      RETURNING VALUE(result) TYPE ty_t_tuple.
    "! CurrentDateMember(hierarchy, format [, EXACT | BEFORE | AFTER]) (CurrentDateMemberUdf): the member whose unique
    "! name is the date of the query formatted with the format, else the closest one; the null member if none.
    METHODS current_date_member
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_member
      RAISING   zzxxmla1_cx_xmla.
    "! Util.lookupCompound with a match type: segment by segment the child of that name; else (BEFORE, AFTER) the
    "! closest sibling (RolapUtil.findBestMemberMatch: by key), then the last (BEFORE) or first (AFTER) child on each
    "! remaining level. Initial if there is none.
    METHODS lookup_member_match
      IMPORTING segments      TYPE zzxxmla1_cl_mdx_node=>ty_t_segment
                match         TYPE string
      RETURNING VALUE(result) TYPE ty_member.
    "! Util.parseIdentifier: the segments of [a].[b] (]] an escaped ]) or of unquoted names.
    CLASS-METHODS parse_identifier
      IMPORTING text          TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_node=>ty_t_segment.
    "! VisualTotals(set [, pattern]) (VisualTotalsFunDef): from the end, a member followed by one of its descendants
    "! becomes a visual total member that totals the descendants following it.
    METHODS visual_totals
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! VisualTotalsFunDef.createMember: a calculated member with the member's unique name, name and level, the caption
    "! of the pattern, solve order 99, that aggregates the stored members it totals.
    METHODS create_visual_total
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
                member        TYPE ty_member
                index         TYPE i
                members       TYPE ty_t_member
      RETURNING VALUE(result) TYPE ty_member
      RAISING   zzxxmla1_cx_xmla.
    "! followingDescendants: the strict descendants after the index; a visual total member without the members after
    "! it that it totals.
    METHODS following_descendants
      IMPORTING member        TYPE ty_member
                index         TYPE i
                members       TYPE ty_t_member
      RETURNING VALUE(result) TYPE ty_t_member.
    "! lastChildIndex: the index after the strict descendants of the member that follow the start.
    METHODS last_child_index
      IMPORTING member        TYPE ty_member
                start         TYPE i
                members       TYPE ty_t_member
      RETURNING VALUE(result) TYPE i.
    "! createListWithRealMember: visual total members replaced by the stored members they total.
    METHODS real_members
      IMPORTING members       TYPE ty_t_member
      RETURNING VALUE(result) TYPE ty_t_member.
    "! The calculation of a visual total member; none for any other member.
    METHODS visual_total_calc
      IMPORTING member        TYPE ty_member
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_mdx_vtotal_calc.
    "! VisualTotalsFunDef.substitute: * is the name, ** an asterisk.
    CLASS-METHODS substitute
      IMPORTING pattern       TYPE string
                name          TYPE string
      RETURNING VALUE(result) TYPE string.
    "! Member.getName: the caption, for a visual total member the name of the member it stands for.
    METHODS name_of
      IMPORTING member        TYPE ty_member
      RETURNING VALUE(result) TYPE string.
    "! &lt;Member&gt;.Properties(name) (PropertiesFunDef, RolapMemberBase.getPropertyValue): a standard property of the
    "! member, else a member property of its level (case-insensitive); null for a property without a value here, also
    "! for a property of a level above (Util.isValidProperty); an error for any other name.
    "! The value of a member property of a level read as text, as the property's type.
    CLASS-METHODS level_property_value
      IMPORTING property      TYPE zzxxmla1_cl_schema=>ty_property
                value         TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value.
    METHODS member_property
      IMPORTING member        TYPE ty_member
                name          TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_mdx_evaluation.
    "! The calculated members of the query in a hierarchy (SchemaReader.getCalculatedMembers), without the placeholders
    "! of a compound slicer.
    METHODS query_calculated_members
      IMPORTING hierarchy     TYPE i
      RETURNING VALUE(result) TYPE ty_t_member.
    "! &lt;Member&gt;.CalculatedChild(name) (CalculatedChildFunDef): the calculated member of the query with that name
    "! below the member, else the null member.
    METHODS calculated_child
      IMPORTING member        TYPE ty_member
                name          TYPE string
      RETURNING VALUE(result) TYPE ty_member.
    "! AddCalculatedMembers(set) (AddCalculatedMembersFunDef): the set, then the calculated members of the query on the
    "! levels of its members that have no parent or the parent of one of them.
    METHODS add_calculated_members
      IMPORTING tuples        TYPE ty_t_tuple
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_mdx_evaluation.
    "! DrilldownLevel(set [, level] [, , index] [, INCLUDE_CALC_MEMBERS]) (DrilldownLevelFunDef): the members, then the
    "! children of those at the level (default: the deepest) not followed by a descendant; with an index each tuple
    "! followed by the tuples with the children of its member at the index.
    METHODS drilldown_level
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! The reference server's Query.getSubcubePredicates: the subcube of the subselects as a predicate on the facts, the predicates
    "! of the axes of every subselect ANDed; none without subselect. Only the form of an axis counts: member sets ({},
    "! in parentheses), - (all but), Head of a member set, CrossJoin (AND), Union (OR), and Members, AllMembers,
    "! Children and Descendants (no restriction); any other function fails the query.
    METHODS subcube_predicate
      IMPORTING query         TYPE zzxxmla1_cl_mdx_parser=>ty_query
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_facts=>ty_t_predicate
      RAISING   zzxxmla1_cx_xmla.
    "! addSetExpressionToSubcubePredicates: the predicates of a set expression, added to sets (indexes in predicate).
    METHODS add_subcube_set
      IMPORTING node      TYPE ty_node
                negated   TYPE abap_bool
      CHANGING  sets      TYPE zzxxmla1_cl_mdx_facts=>ty_t_index
                predicate TYPE zzxxmla1_cl_mdx_facts=>ty_t_predicate
      RAISING   zzxxmla1_cx_xmla.
    "! addSetToSubcubePredicates: a set of members ({}) as the OR of their predicates (the key columns of their levels
    "! equal to their keys), negated NOT; the All member has none. limit: the first so many members only (Head).
    METHODS add_subcube_members
      IMPORTING node      TYPE ty_node
                negated   TYPE abap_bool
                limit     TYPE i DEFAULT -1
      CHANGING  sets      TYPE zzxxmla1_cl_mdx_facts=>ty_t_index
                predicate TYPE zzxxmla1_cl_mdx_facts=>ty_t_predicate
      RAISING   zzxxmla1_cx_xmla.
    "! A subselect the reference server cannot turn into a predicate (UnsupportedOperationException): the query fails.
    CLASS-METHODS unsupported_subcube
      IMPORTING message TYPE string
      RAISING   zzxxmla1_cx_xmla.
    "! The DIMENSION PROPERTIES of an axis and their values for its members (Olap4jCellSetAxisMetaData):
    "! MEMBER_VALUE is skipped, a single name is one of olap4j's standard member properties, more segments are a level
    "! and one of its member properties (Util.lookup with allowProp, Util.lookupProperty); anything else is not found.
    METHODS axis_properties
      IMPORTING query_axis TYPE zzxxmla1_cl_mdx_parser=>ty_axis
      CHANGING  axis       TYPE ty_axis
      RAISING   zzxxmla1_cx_xmla.
    "! A DIMENSION PROPERTIES entry that names no property (MdxChildObjectNotFound).
    METHODS property_not_found
      IMPORTING name TYPE string
      RAISING   zzxxmla1_cx_xmla.
    "! The value of a standard member property as XMLA writes it (Olap4jMember.getPropertyValue).
    "! @parameter found | false: the member has no value of it, it is left out
    METHODS dimension_property
      IMPORTING member TYPE ty_member
                name   TYPE string
      EXPORTING value  TYPE string
                found  TYPE abap_bool
      RAISING   zzxxmla1_cx_xmla.
    "! the query asks for the cell property FORMAT_STRING
    DATA want_format_string TYPE abap_bool.
    "! DrilldownMember(set1, set2 [, RECURSIVE]) (DrilldownMemberFunDef): each tuple of set1, then for its first member
    "! that is in set2 the tuple with each child of it in that place (and with RECURSIVE their drill-downs). Excel
    "! expands a member so; its INCLUDE_CALC_MEMBERS (the fifth argument) is ignored, as the reference does.
    METHODS drilldown_member
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    TYPES ty_unique_names TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    "! DrilldownMemberFunDef.drillDownObj: the drill-down of one tuple, added to the result.
    METHODS drilldown_member_tuple
      IMPORTING tuple     TYPE ty_tuple
                drilled   TYPE ty_unique_names
                recursive TYPE abap_bool
      CHANGING  result    TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! LastNonEmpty(set, value) (LastNonEmptyUdf): the last member of the set with a value, else the null member.
    METHODS last_non_empty
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_member
      RAISING   zzxxmla1_cx_xmla.
    "! Mod(n, d) (Excel.mod): n - d * floor(n / d); null if an argument is null (JavaFunDef).
    METHODS modulo
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_xmla.
    "! CInt(value) (Vba.cInt): a number rounded half to even, a text parsed; null if the value is null (JavaFunDef).
    CLASS-METHODS java_cint
      IMPORTING value         TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_mdx_evaluation.
    "! Format(value, format string) (FormatFunDef): util.Format of the value.
    METHODS format
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_xmla.
    "! CASE (CaseTestFunDef, CaseMatchFunDef): the result of the first true condition or equal match, else the default
    "! (null if there is none).
    METHODS case
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RAISING   zzxxmla1_cx_xmla.
    "! &lt;Member&gt; IN &lt;Set&gt; (InUdf): whether a member of the set has the member's unique name.
    METHODS member_in_set
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE abap_bool
      RAISING   zzxxmla1_cx_xmla.
    "! &lt;String&gt; MATCHES &lt;String&gt; (MatchesUdf): Java's Pattern.matches(regex, text).
    METHODS string_matches
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE abap_bool
      RAISING   zzxxmla1_cx_xmla.
    "! Whether the whole text matches a Java regular expression, as Pattern.matches. The expression is translated to
    "! ABAP's POSIX syntax: leading inline flags (?i) become case-insensitive matching, \Q...\E quotes its characters.
    CLASS-METHODS java_matches
      IMPORTING text          TYPE string
                regex         TYPE string
      RETURNING VALUE(result) TYPE abap_bool
      RAISING   zzxxmla1_cx_mdx_evaluation.
    "! &lt;Expression&gt; IS &lt;Expression&gt; (IsFunDef): two tuples of equal members, else the same object (members
    "! by unique name).
    METHODS is_same
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE abap_bool
      RAISING   zzxxmla1_cx_xmla.
    "! Existing &lt;Set&gt; (ExistingFunDef): the tuples that exist with the members of the context.
    METHODS existing
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! Exists(&lt;Set1&gt;, &lt;Set2&gt;) (ExistsFunDef): the tuples of the first set that exist with a tuple of the second.
    METHODS exists
      IMPORTING evaluator     TYPE ty_evaluator
                node          TYPE ty_node
      RETURNING VALUE(result) TYPE ty_t_tuple
      RAISING   zzxxmla1_cx_xmla.
    "! FunUtil.existsInTuple: every member of each tuple is on the same hierarchy chain as the corresponding member of
    "! the other tuple: the member of its hierarchy there, else the context member (with an evaluator) or the default
    "! member of the hierarchy.
    METHODS exists_in_tuple
      IMPORTING left          TYPE ty_tuple
                right         TYPE ty_tuple
                evaluator     TYPE ty_evaluator OPTIONAL
      RETURNING VALUE(result) TYPE abap_bool.
    METHODS corresponding_member
      IMPORTING member        TYPE ty_member
                tuple         TYPE ty_tuple
                evaluator     TYPE ty_evaluator OPTIONAL
      RETURNING VALUE(result) TYPE ty_member.
    "! member.isOnSameHierarchyChain( other ): other.isOnSameHierarchyChainInternal( member ), except for the
    "! placeholder of a compound slicer, which decides itself.
    METHODS is_on_same_hierarchy_chain
      IMPORTING member        TYPE ty_member
                other         TYPE ty_member
      RETURNING VALUE(result) TYPE abap_bool.
    "! MemberBase.isOnSameHierarchyChainInternal: one is an ancestor of the other or the same member. The placeholder of
    "! a compound slicer (CompoundSlicerRolapMember): the other is on the chain of the member of a slicer tuple; the
    "! position of that member is found in the first member of the first tuple only, as the reference does.
    METHODS is_on_same_chain_internal
      IMPORTING member        TYPE ty_member
                other         TYPE ty_member
      RETURNING VALUE(result) TYPE abap_bool.
    "! FunUtil.isAncestorOf( ancestor, member, false ): the member or one of its ancestors is the ancestor.
    METHODS is_ancestor_of
      IMPORTING ancestor      TYPE ty_member
                member        TYPE ty_member
      RETURNING VALUE(result) TYPE abap_bool.
    "! The slicer tuples of the placeholder of a compound slicer; none for any other member.
    METHODS compound_slicer_tuples
      IMPORTING member        TYPE ty_member
      RETURNING VALUE(result) TYPE ty_t_tuple.
    "! OrderKey.compareTo: calculated members after the others, then RolapMemberBase.compareTo (CompareSiblingsByOrderKey
    "! is off): by key, numbers as numbers, strings case-sensitively after ignoring case; keys of different kinds by
    "! unique name.
    CLASS-METHODS compare_order_keys
      IMPORTING member1       TYPE ty_member
                member2       TYPE ty_member
      RETURNING VALUE(result) TYPE i.
    "! An error of the reference (an Exception while the query executes): the query fails.
    CLASS-METHODS execute_error
      IMPORTING message TYPE string
      RAISING   zzxxmla1_cx_xmla.
    "! GenericCalc.msg: Expected value of type T; got value 'v' (actual type).
    CLASS-METHODS type_error
      IMPORTING expected      TYPE string
                value         TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cx_mdx_evaluation.
    METHODS set_display_info
      CHANGING tuples TYPE ty_t_tuple.
    METHODS fail
      IMPORTING message TYPE string
      RAISING   zzxxmla1_cx_xmla.
ENDCLASS.

CLASS zzxxmla1_cl_mdx_engine IMPLEMENTATION.

  METHOD constructor.
    me->catalog = catalog.
  ENDMETHOD.

  METHOD execute.
    schema_reader = zzxxmla1_cl_mdx_schema_reader=>for_cube( catalog = catalog name = query-cube ).
    DATA(cube) = schema_reader->cube.
    fact_reader = NEW zzxxmla1_cl_mdx_facts( cube = cube hierarchies = schema_reader->get_model_hierarchies( )
                                             measures = schema_reader->measures ).
    DATA(resolved) = query.
    DATA(validator) = NEW zzxxmla1_cl_mdx_validator( schema_reader ).
    validator->resolve_query( CHANGING query = resolved ).
    query_measures = validator->get_measures_members( ).
    CLEAR context_paths_cache.
    " the subcube of a subselect restricts every read of facts
    fact_reader->set_subcube( subcube_predicate( resolved ) ).
    root_evaluator = zzxxmla1_cl_mdx_evaluator=>create( schema_reader = schema_reader facts = fact_reader calc = me ).
    DATA(evaluator) = CAST zzxxmla1_if_mdx_evaluator( root_evaluator ).
    CLEAR: named_set_values, cell_slicer.
    slicer_evaluator_context = evaluator->get_members( ).

    DATA(non_all_members) = load_special_members( evaluator ).

    " the slicer, in the default context; its members are then the context of the axes and of the cells. Its members
    " replace the root members of their hierarchies (Determine Slicer), then it is executed (Execute Slicer).
    IF resolved-slicer IS BOUND.
      DATA(slicer_members) = VALUE ty_t_member( ).
      LOOP AT execute_axis( evaluator = evaluator expression = resolved-slicer non_empty = abap_false )
           INTO DATA(slicer_tuple).
        LOOP AT slicer_tuple INTO DATA(slicer_member).
          IF NOT line_exists( slicer_members[ unique_name = slicer_member-unique_name ] ).
            APPEND slicer_member TO slicer_members.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
      replace_non_all_members( EXPORTING members = slicer_members CHANGING lists = non_all_members ).
      DATA(slicer) = eval_execute( evaluator = evaluator lists = non_all_members index = lines( non_all_members )
                                   expression = resolved-slicer non_empty = abap_false ).
      IF slicer IS INITIAL.
        fail( `The slicer must not be empty` ).
      ENDIF.
      result-has_slicer = abap_true.
      result-slicer = slicer.
      DATA(slicer_context) = COND ty_t_member( WHEN lines( slicer ) = 1 THEN slicer[ 1 ]
                                               ELSE compound_slicer( tuples = slicer members = slicer_members ) ).
      evaluator->set_slicer_context( slicer_context ).
      slicer_evaluator_context = evaluator->get_members( ).
      cell_slicer = slicer_context.
    ENDIF.

    " the axes in the order of their ordinals (the validator made sure they follow each other from 0). The top members
    " of their members replace the root members of their hierarchies (Determine Axes).
    DATA(query_axes) = resolved-axes.
    SORT query_axes BY ordinal ASCENDING.
    IF non_all_members IS NOT INITIAL.
      DATA(axis_members) = VALUE ty_t_member( ).
      LOOP AT query_axes INTO DATA(query_axis).
        LOOP AT top_members( execute_axis( evaluator = evaluator expression = query_axis-expression
                                           non_empty = query_axis-non_empty ) ) INTO DATA(axis_member).
          IF NOT line_exists( axis_members[ unique_name = axis_member-unique_name ] ).
            APPEND axis_member TO axis_members.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
      replace_non_all_members( EXPORTING members = axis_members CHANGING lists = non_all_members ).
    ENDIF.

    " Execute Axes: again without the dimension of a calculated member that starts an axis (redo)
    DO.
      DATA(redo) = abap_false.
      CLEAR result-axes.
      LOOP AT query_axes INTO query_axis.
        DATA(tuples) = eval_execute( evaluator = evaluator lists = non_all_members index = lines( non_all_members )
                                     expression = query_axis-expression non_empty = query_axis-non_empty ).
        IF non_all_members IS NOT INITIAL AND tuples IS NOT INITIAL.
          LOOP AT tuples[ 1 ] INTO DATA(first) WHERE calculated = abap_true.
            " a visual total: the dimension of the members it aggregates, its own
            DATA(dimension) = COND i( WHEN first-calc_name IS NOT INITIAL THEN schema_reader->dimension_of( first-hier_id )
                                      ELSE last_dimension( schema_reader->get_calculation( first )-expression ) ).
            LOOP AT non_all_members INTO DATA(list).
              IF schema_reader->dimension_of( list[ 1 ]-hier_id ) = dimension.
                DELETE non_all_members INDEX sy-tabix.
                redo = abap_true.
                EXIT.
              ENDIF.
            ENDLOOP.
          ENDLOOP.
        ENDIF.
        APPEND VALUE #( name = |Axis{ query_axis-ordinal }| tuples = tuples
                        hierarchies = type_hierarchies( query_axis-expression->get_type( ) ) ) TO result-axes.
      ENDLOOP.
      IF redo = abap_false.
        EXIT.
      ENDIF.
    ENDDO.

    result-cube_name = cube-cube_name.
    " cut the fraction of the seconds as cl_abap_tstmp=>move_to_short does (not in 7.50); rounding could give second 60
    result-last_update = trunc( cube-generated_at ).
    " the cell properties: the name of each (its first segment), in upper case
    LOOP AT resolved-cell_properties INTO DATA(cell_property).
      SPLIT cell_property AT `.` INTO cell_property DATA(rest) ##NEEDED.
      IF cell_property CP `[*]`.
        cell_property = substring( val = cell_property off = 1 len = strlen( cell_property ) - 2 ).
      ENDIF.
      APPEND to_upper( cell_property ) TO result-cell_properties.
    ENDLOOP.
    IF result-cell_properties IS INITIAL.
      result-cell_properties = VALUE #( ( `VALUE` ) ( `FORMATTED_VALUE` ) ).
    ENDIF.
    want_format_string = xsdbool( line_exists( result-cell_properties[ table_line = `FORMAT_STRING` ] ) ).

    " one cell per combination of the axes' tuples; no axis is one cell, an empty axis none (executeBody)
    DATA(body) = evaluator->savepoint( ).
    evaluator->set_cell_reader( ).
    execute_stripe( EXPORTING evaluator = evaluator axes = result-axes slicer = slicer_context
                              axis_index = lines( result-axes )
                    CHANGING  cells = result-cells ).
    evaluator->restore( body ).

    LOOP AT query_axes INTO query_axis WHERE non_empty = abap_true.
      remove_empty_positions( EXPORTING position = query_axis-ordinal + 1 CHANGING result = result ).
    ENDLOOP.

    LOOP AT result-axes ASSIGNING FIELD-SYMBOL(<axis>).
      set_display_info( CHANGING tuples = <axis>-tuples ).
    ENDLOOP.
    " the slicer axis too: one tuple shows only the number of children, the tuples of a compound slicer also the flags
    set_display_info( CHANGING tuples = result-slicer ).

    LOOP AT result-axes ASSIGNING <axis>.
      axis_properties( EXPORTING query_axis = query_axes[ sy-tabix ] CHANGING axis = <axis> ).
    ENDLOOP.
  ENDMETHOD.

  METHOD drill_through.
    DATA(executed) = execute( statement-query ).
    DATA(items) = drill_through_items( statement-return_list ).

    " the cell of the coordinates 0 (CellSet.getCell): the first tuple of every axis in the context of the slicer, as
    " execute_stripe sets it; an empty axis has no cell
    LOOP AT executed-axes TRANSPORTING NO FIELDS WHERE tuples IS INITIAL.
      drill_through_error( `Cannot do DrillThrough operation on the cell` ).
    ENDLOOP.
    DATA(evaluator) = CAST zzxxmla1_if_mdx_evaluator( root_evaluator ).
    DATA(savepoint) = evaluator->savepoint( ).
    DATA(axis_index) = lines( executed-axes ).
    WHILE axis_index > 0.
      evaluator->set_context_members( executed-axes[ axis_index ]-tuples[ 1 ] ).
      axis_index = axis_index - 1.
    ENDWHILE.
    evaluator->set_context_members( cell_slicer ).
    " getMembersForDrillThrough: the members of the cell, a trivial calculated member replaced by its member
    DATA(members) = evaluator->get_members( ).
    evaluator->restore( savepoint ).
    LOOP AT members ASSIGNING FIELD-SYMBOL(<member>) WHERE calculated = abap_true.
      <member> = trivial_member( <member> ).
    ENDLOOP.

    " a compound slicer (buildDrillthroughSlicerPredicate): the hierarchies whose member is not the one of every
    " position are not constrained by the cell; the positions restrict the facts instead, each the AND of its members of
    " those hierarchies, all of them ORed
    DATA free TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    DATA slicer TYPE zzxxmla1_cl_mdx_facts=>ty_t_predicate.
    IF lines( executed-slicer ) > 1.
      LOOP AT executed-slicer INTO DATA(position).
        LOOP AT position INTO DATA(slicer_member).
          IF members[ slicer_member-hier_id + 1 ]-unique_name <> slicer_member-unique_name
              AND NOT line_exists( free[ table_line = slicer_member-hier_id ] ).
            APPEND slicer_member-hier_id TO free.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
      APPEND VALUE #( kind = zzxxmla1_cl_mdx_facts=>c_predicate-or ) TO slicer.
      DATA disjuncts TYPE zzxxmla1_cl_mdx_facts=>ty_t_index.
      LOOP AT executed-slicer INTO position.
        DATA(conjuncts) = VALUE zzxxmla1_cl_mdx_facts=>ty_t_index( ).
        LOOP AT position INTO slicer_member.
          IF line_exists( free[ table_line = slicer_member-hier_id ] ) AND slicer_member-key_level > 0.
            APPEND VALUE #( kind   = zzxxmla1_cl_mdx_facts=>c_predicate-member
                            member = VALUE #( hierarchy = slicer_member-hier_id level = slicer_member-key_level
                                              path      = slicer_member-path ) ) TO slicer.
            APPEND lines( slicer ) TO conjuncts.
          ENDIF.
        ENDLOOP.
        APPEND VALUE #( kind = zzxxmla1_cl_mdx_facts=>c_predicate-and children = conjuncts ) TO slicer.
        APPEND lines( slicer ) TO disjuncts.
      ENDLOOP.
      slicer[ 1 ]-children = disjuncts.
    ENDIF.

    " canDrillThrough: no calculated member but a measure; a null member has no cell (makeCellRequest)
    DATA filters TYPE zzxxmla1_cl_mdx_facts=>ty_t_filter.
    LOOP AT members INTO DATA(member) FROM 2.
      IF line_exists( free[ table_line = member-hier_id ] ).
        APPEND VALUE #( hierarchy = member-hier_id ) TO filters.
        CONTINUE.
      ENDIF.
      IF member-calculated = abap_true OR member-is_null = abap_true.
        drill_through_error( `Cannot do DrillThrough operation on the cell` ).
      ENDIF.
      APPEND VALUE #( hierarchy = member-hier_id level = member-key_level path = member-path ) TO filters.
    ENDLOOP.
    " the measure of the cell; for a calculated one the first measure of the cube
    DATA(measure) = members[ 1 ].
    result = fact_reader->drill_through(
      members   = filters
      measure   = COND #( WHEN measure-calculated = abap_false THEN measure-measure_index ELSE 1 )
      slicer    = slicer
      items     = items
      max_rows  = statement-max_rows
      first_row = statement-first_rowset ).
  ENDMETHOD.

  METHOD trivial_member.
    result = member.
    IF member-calc_name IS NOT INITIAL.
      RETURN.
    ENDIF.
    DATA(expression) = schema_reader->get_calculation( member )-expression.
    IF expression IS NOT BOUND.
      RETURN.
    ENDIF.
    IF expression->kind = zzxxmla1_cl_mdx_node=>c_kind-member.
      result = expression->element-member.
    ELSEIF expression->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call
        AND to_upper( expression->fun_def-name ) = `AGGREGATE` AND expression->args IS NOT INITIAL.
      DATA(set) = expression->args[ 1 ].
      IF set->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call AND set->fun_def-name = `{}`
          AND lines( set->args ) = 1 AND set->args[ 1 ]->kind = zzxxmla1_cl_mdx_node=>c_kind-member.
        result = set->args[ 1 ]->element-member.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD drill_through_items.
    LOOP AT return_list INTO DATA(node).
      DATA(element) = schema_reader->lookup_compound( node->segments ).
      DATA hierarchy TYPE i.
      hierarchy = -1.
      CASE element-kind.
        WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-level.
          DATA(level) = schema_reader->get_level( element-id ).
          IF level-key_level > 0.
            APPEND VALUE #( hierarchy = level-hierarchy level = level-key_level ) TO result.
          ENDIF.
        WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-hierarchy.
          hierarchy = element-id.
        WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-dimension.
          DATA(dimension) = schema_reader->get_dimension( element-id ).
          hierarchy = dimension-hierarchies[ 1 ].
        WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-member.
          DATA(member) = element-member.
          IF member-hier_id <> zzxxmla1_cl_mdx_schema_reader=>c_measures.
            drill_through_error( `olap4abap Error:Unknown member type in DRILLTHROUGH operation.` ).
          ELSEIF member-calculated = abap_true.
            drill_through_error( |olap4abap Error:Can't perform drillthrough operations because | &&
                                 |'{ member-unique_name }' is a calculated member.| ).
          ENDIF.
          APPEND VALUE #( measure = member-measure_index ) TO result.
        WHEN OTHERS.
          drill_through_error( |olap4abap Error:MDX object '{ node->unparse( ) }' not found in cube | &&
                               |'{ schema_reader->cube-cube_name }'| ).
      ENDCASE.
      " a hierarchy or a dimension: the first level of the hierarchy below its All level; Measures has none
      IF hierarchy > 0.
        APPEND VALUE #( hierarchy = hierarchy level = 1 ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD drill_through_error.
    zzxxmla1_cx_xmla=>raise_code( kind = `Server` code = `00HSBF02` text = `XMLA Drill Through SQL error`
                                  description = message ).
  ENDMETHOD.

  METHOD subcube_predicate.
    " the root: the AND of the predicates of all axes of all subselects
    APPEND VALUE #( kind = zzxxmla1_cl_mdx_facts=>c_predicate-and ) TO result.
    DATA sets TYPE zzxxmla1_cl_mdx_facts=>ty_t_index.
    LOOP AT query-subcubes INTO DATA(subcube).
      LOOP AT subcube-axes INTO DATA(axis).
        add_subcube_set( EXPORTING node = axis-expression negated = abap_false
                         CHANGING  sets = sets predicate = result ).
      ENDLOOP.
    ENDLOOP.
    IF sets IS INITIAL.
      CLEAR result.
      RETURN.
    ENDIF.
    result[ 1 ]-children = sets.
  ENDMETHOD.

  METHOD add_subcube_set.
    IF node->kind <> zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
      unsupported_subcube( |Unsupported expression type in subcube axis: { node->unparse( ) }| ).
    ENDIF.
    DATA(name) = node->fun_def-name.
    CASE to_upper( name ).
      WHEN `()`.
        LOOP AT node->args INTO DATA(arg).
          add_subcube_set( EXPORTING node = arg negated = negated CHANGING sets = sets predicate = predicate ).
        ENDLOOP.
      WHEN `{}`.
        add_subcube_members( EXPORTING node = node negated = negated CHANGING sets = sets predicate = predicate ).
      WHEN `-`.
        " - <Set> and <Set> - <Set> alike: the first operand, negated
        add_subcube_set( EXPORTING node = node->args[ 1 ] negated = xsdbool( negated = abap_false )
                         CHANGING  sets = sets predicate = predicate ).
      WHEN `HEAD`.
        DATA(count) = -1.
        IF lines( node->args ) = 2.
          DATA(count_node) = node->args[ 2 ].
          IF count_node->kind <> zzxxmla1_cl_mdx_node=>c_kind-literal
              OR count_node->category <> zzxxmla1_cl_mdx_node=>c_category-numeric.
            unsupported_subcube( |Head count in subcube must be a numeric literal: { count_node->unparse( ) }| ).
          ENDIF.
          count = trunc( CONV decfloat34( count_node->value ) ).
          IF count < 0.
            unsupported_subcube( |Head count in subcube cannot be negative: { count }| ).
          ENDIF.
          IF count = 0.
            " Head(set, 0) admits nothing; NOT Head(set, 0) everything
            IF negated = abap_false.
              APPEND VALUE #( kind = zzxxmla1_cl_mdx_facts=>c_predicate-false ) TO predicate.
              APPEND lines( predicate ) TO sets.
            ENDIF.
            RETURN.
          ENDIF.
        ENDIF.
        DATA(head_set) = node->args[ 1 ].
        IF count >= 0 AND head_set->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call AND head_set->fun_def-name = `{}`.
          add_subcube_members( EXPORTING node = head_set negated = negated limit = count
                               CHANGING  sets = sets predicate = predicate ).
        ELSE.
          add_subcube_set( EXPORTING node = head_set negated = negated CHANGING sets = sets predicate = predicate ).
        ENDIF.
      WHEN `CROSSJOIN` OR `NONEMPTYCROSSJOIN`.
        IF lines( node->args ) <> 2.
          unsupported_subcube( |{ name } in subcube must have 2 args: { node->unparse( ) }| ).
        ENDIF.
        add_subcube_set( EXPORTING node = node->args[ 1 ] negated = negated CHANGING sets = sets predicate = predicate ).
        add_subcube_set( EXPORTING node = node->args[ 2 ] negated = negated CHANGING sets = sets predicate = predicate ).
      WHEN `UNION`.
        DATA left TYPE zzxxmla1_cl_mdx_facts=>ty_t_index.
        DATA right TYPE zzxxmla1_cl_mdx_facts=>ty_t_index.
        add_subcube_set( EXPORTING node = node->args[ 1 ] negated = negated CHANGING sets = left predicate = predicate ).
        add_subcube_set( EXPORTING node = node->args[ 2 ] negated = negated CHANGING sets = right predicate = predicate ).
        IF left IS NOT INITIAL AND right IS NOT INITIAL.
          " each side the AND of its predicates
          DATA(sides) = VALUE zzxxmla1_cl_mdx_facts=>ty_t_index( ).
          DO 2 TIMES.
            DATA(parts) = COND zzxxmla1_cl_mdx_facts=>ty_t_index( WHEN sy-index = 1 THEN left ELSE right ).
            IF lines( parts ) = 1.
              APPEND parts[ 1 ] TO sides.
            ELSE.
              APPEND VALUE #( kind = zzxxmla1_cl_mdx_facts=>c_predicate-and children = parts ) TO predicate.
              APPEND lines( predicate ) TO sides.
            ENDIF.
          ENDDO.
          IF negated = abap_true.
            " NOT (a OR b) is NOT a AND NOT b: both sides on their own
            APPEND LINES OF sides TO sets.
          ELSE.
            APPEND VALUE #( kind = zzxxmla1_cl_mdx_facts=>c_predicate-or children = sides ) TO predicate.
            APPEND lines( predicate ) TO sets.
          ENDIF.
        ENDIF.
      WHEN `FILTER`.
        " The reference server turns some conditions on member keys into predicates; not ported yet
        unsupported_subcube( |Filter in a subselect is not implemented yet: { node->unparse( ) }| ).
      WHEN `ALLMEMBERS` OR `MEMBERS` OR `CHILDREN` OR `DESCENDANTS`.
        " all or descendants of members of a hierarchy: no restriction
      WHEN OTHERS.
        unsupported_subcube( |Unsupported function in subcube axis: { name }| ).
    ENDCASE.
  ENDMETHOD.

  METHOD add_subcube_members.
    DATA members TYPE zzxxmla1_cl_mdx_facts=>ty_t_index.
    LOOP AT node->args INTO DATA(arg).
      IF limit >= 0 AND sy-tabix > limit.
        EXIT.
      ENDIF.
      IF arg->kind <> zzxxmla1_cl_mdx_node=>c_kind-member.
        unsupported_subcube( |Unsupported expression type in subcube set: { arg->unparse( ) }| ).
      ENDIF.
      DATA(member) = arg->element-member.
      IF member-calculated = abap_true OR member-is_null = abap_true
          OR member-hier_id = zzxxmla1_cl_mdx_schema_reader=>c_measures.
        unsupported_subcube( |Unsupported member in subcube set: { member-unique_name }| ).
      ENDIF.
      " the All member restricts nothing: it has no key column
      IF member-key_level = 0.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( kind   = zzxxmla1_cl_mdx_facts=>c_predicate-member
                      member = VALUE #( hierarchy = member-hier_id level = member-key_level path = member-path ) )
             TO predicate.
      APPEND lines( predicate ) TO members.
    ENDLOOP.
    IF members IS INITIAL.
      RETURN.
    ENDIF.
    APPEND VALUE #( kind = zzxxmla1_cl_mdx_facts=>c_predicate-or children = members ) TO predicate.
    IF negated = abap_true.
      APPEND VALUE #( kind = zzxxmla1_cl_mdx_facts=>c_predicate-not children = VALUE #( ( lines( predicate ) ) ) )
             TO predicate.
    ENDIF.
    APPEND lines( predicate ) TO sets.
  ENDMETHOD.

  METHOD unsupported_subcube.
    zzxxmla1_cx_xmla=>raise_code( kind = `Server` code = `00HSBD02` text = `XMLA MDX execute failed`
                                  description = message ).
  ENDMETHOD.

  METHOD axis_properties.
    DATA(standard) = VALUE string_table(
      ( `CATALOG_NAME` ) ( `SCHEMA_NAME` ) ( `CUBE_NAME` ) ( `DIMENSION_UNIQUE_NAME` ) ( `HIERARCHY_UNIQUE_NAME` )
      ( `LEVEL_UNIQUE_NAME` ) ( `LEVEL_NUMBER` ) ( `MEMBER_ORDINAL` ) ( `MEMBER_NAME` ) ( `MEMBER_UNIQUE_NAME` )
      ( `MEMBER_TYPE` ) ( `MEMBER_GUID` ) ( `MEMBER_CAPTION` ) ( `CHILDREN_CARDINALITY` ) ( `PARENT_LEVEL` )
      ( `PARENT_UNIQUE_NAME` ) ( `PARENT_COUNT` ) ( `DESCRIPTION` ) ( `$visible` ) ( `MEMBER_KEY` )
      ( `IS_PLACEHOLDERMEMBER` ) ( `IS_DATAMEMBER` ) ( `DEPTH` ) ( `DISPLAY_INFO` ) ( `VALUE` ) ).
    LOOP AT query_axis-dimension_properties INTO DATA(id).
      DATA(name) = id->segments[ 1 ]-name.
      IF lines( id->segments ) = 1.
        IF name = `MEMBER_VALUE`.
          CONTINUE.
        ENDIF.
        IF NOT line_exists( standard[ table_line = name ] ).
          property_not_found( name ).
        ENDIF.
        APPEND name TO axis-properties.
        CONTINUE.
      ENDIF.
      " a member property of a level: the level the segments but the last name, with a property of the last name
      name = id->segments[ lines( id->segments ) ]-name.
      DATA(segments) = id->segments.
      DELETE segments INDEX lines( segments ).
      DATA(element) = schema_reader->lookup_compound( segments = segments
                                                      category = zzxxmla1_cl_mdx_type=>c_category-level ).
      IF element-kind <> zzxxmla1_cl_mdx_schema_reader=>c_element-level
          OR id->segments[ lines( id->segments ) ]-quoting = zzxxmla1_cl_mdx_node=>c_quoting-key
          OR schema_reader->is_valid_property( level = element-id name = name ) = abap_false.
        property_not_found( id->unparse( ) ).
      ENDIF.
      DATA(property) = schema_reader->lookup_level_property( level = element-id name = name ).
      IF property IS INITIAL.
        execute_error( |Standard properties of a level in DIMENSION PROPERTIES are not implemented yet: | &&
                       id->unparse( ) ).
      ENDIF.
      APPEND name TO axis-properties.
      " olap4j's datatype of the property as XML schema type (XmlaHandler.getXsdType)
      APPEND VALUE #( name      = name
                      hierarchy = schema_reader->get_hierarchy( schema_reader->get_level( element-id )-hierarchy
                                                                )-unique_name
                      xsd_type  = SWITCH #( property-data_type WHEN `Numeric` THEN `xsd:double`
                                                               WHEN `Integer` THEN `xsd:int`
                                                               WHEN `Long` THEN `xsd:long`
                                                               WHEN `Boolean` THEN `xsd:boolean`
                                                               ELSE `xsd:string` ) ) TO axis-level_properties.
    ENDLOOP.
    IF axis-properties IS INITIAL.
      RETURN.
    ENDIF.
    DATA done TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    LOOP AT axis-tuples INTO DATA(tuple).
      LOOP AT tuple INTO DATA(member).
        INSERT member-unique_name INTO TABLE done.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
        LOOP AT axis-properties INTO name.
          " a property of a level: the value of a member of its hierarchy that has one (getHierarchyProperty)
          READ TABLE axis-level_properties INTO DATA(level_property) WITH KEY name = name.
          IF sy-subrc = 0.
            IF level_property-hierarchy = member-hierarchy.
              schema_reader->get_property_value( EXPORTING member   = member
                                                           name     = name
                                                 IMPORTING property = DATA(property_definition)
                                                           value    = DATA(text)
                                                           found    = DATA(has_property) ).
              DATA(typed) = level_property_value( property = property_definition value = text ).
              IF has_property = abap_true AND typed-empty = abap_false.
                INSERT VALUE #( member = member-unique_name name = name
                                value  = zzxxmla1_cl_mdx_evaluator=>to_text( typed ) ) INTO TABLE axis-values.
              ENDIF.
            ENDIF.
            CONTINUE.
          ENDIF.
          dimension_property( EXPORTING member = member name = name IMPORTING value = DATA(value) found = DATA(found) ).
          IF found = abap_true.
            INSERT VALUE #( member = member-unique_name name = name value = value ) INTO TABLE axis-values.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD property_not_found.
    zzxxmla1_cx_xmla=>raise_code(
      kind = `Client` code = `00HSBD01` text = `XMLA MDX parse failed`
      description = |olap4abap Error:MDX object '{ name }' not found in cube '{ schema_reader->cube-cube_name }'| ).
  ENDMETHOD.

  METHOD dimension_property.
    CLEAR value.
    found = abap_true.
    DATA(measure) = xsdbool( member-hier_id = zzxxmla1_cl_mdx_schema_reader=>c_measures ).
    CASE name.
      WHEN `CATALOG_NAME` OR `CUBE_NAME` OR `MEMBER_GUID` OR `DESCRIPTION` OR `IS_PLACEHOLDERMEMBER` OR `IS_DATAMEMBER`
        OR `VALUE` OR `DISPLAY_INFO`.
        " no value here; DISPLAY_INFO is the member's in its tuple
        found = abap_false.
      WHEN `SCHEMA_NAME`.
        value = schema_reader->cube-catalog_name.
      WHEN `MEMBER_ORDINAL`.
        " a measure's position in the cube, 0 for the All member, else unset (-1)
        " (a template: a negative number moved to a string gets its sign last)
        value = |{ COND i( WHEN measure = abap_true AND member-calculated = abap_false THEN member-measure_index - 1
                           WHEN member-key_level = 0 AND member-calculated = abap_false AND measure = abap_false
                                AND member-is_null = abap_false THEN 0
                           ELSE -1 ) }|.
      WHEN `$visible`.
        value = `true`.
      WHEN `DEPTH`.
        value = |{ depth_of( member ) }|.
      WHEN OTHERS.
        IF name = `MEMBER_KEY` AND measure = abap_true.
          " a measure's key is its name
          value = member-caption.
          RETURN.
        ENDIF.
        TRY.
            DATA(property) = member_property( member = member name = name ).
          CATCH zzxxmla1_cx_mdx_evaluation INTO DATA(error).
            execute_error( error->to_text( ) ).
        ENDTRY.
        IF property-empty = abap_true.
          found = abap_false.
        ELSE.
          value = zzxxmla1_cl_mdx_evaluator=>to_text( property ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD execute_axis.
    DATA(savepoint) = evaluator->savepoint( ).
    evaluator->set_non_empty( non_empty ).
    evaluator->set_eval_axes( abap_true ).
    TRY.
        result = evaluate_set( evaluator = evaluator node = expression ).
        IF non_empty = abap_true.
          result = non_empty_axis( evaluator = evaluator tuples = result ).
        ENDIF.
      CLEANUP.
        evaluator->restore( savepoint ).
    ENDTRY.
    evaluator->restore( savepoint ).
  ENDMETHOD.

  METHOD non_empty_axis.
    " the set is evaluated non-empty (execute_axis); each tuple, then each measure, is set in the context, which is
    " not restored before the next
    DATA(savepoint) = evaluator->savepoint( ).
    TRY.
        LOOP AT tuples INTO DATA(tuple).
          IF query_measures IS INITIAL.
            evaluator->set_context_members( tuple ).
            IF evaluator->evaluate_current( )-empty = abap_false.
              APPEND tuple TO result.
            ENDIF.
            CONTINUE.
          ENDIF.
          LOOP AT query_measures INTO DATA(measure).
            evaluator->set_context_members( tuple ).
            evaluator->set_context( measure ).
            IF evaluator->evaluate_current( )-empty = abap_false.
              APPEND tuple TO result.
              EXIT.
            ENDIF.
          ENDLOOP.
        ENDLOOP.
      CLEANUP.
        evaluator->restore( savepoint ).
    ENDTRY.
    evaluator->restore( savepoint ).
  ENDMETHOD.

  METHOD non_empty_level_members.
    result = schema_reader->get_level_members( level ).
    IF evaluator->is_non_empty( ) = abap_true AND lines( result ) > c_level_pre_cache_threshold.
      result = context_members( evaluator = evaluator members = result ).
    ENDIF.
  ENDMETHOD.

  METHOD non_empty_children.
    result = schema_reader->get_member_children( member ).
    IF evaluator->is_non_empty( ) = abap_false OR result IS INITIAL.
      RETURN.
    ENDIF.
    DATA(savepoint) = evaluator->savepoint( ).
    evaluator->set_context( member ).
    result = context_members( evaluator = evaluator members = result ).
    evaluator->restore( savepoint ).
  ENDMETHOD.

  METHOD context_members.
    result = members.
    IF members IS INITIAL OR evaluator->is_non_empty( ) = abap_false.
      RETURN.
    ENDIF.
    DATA(hierarchy) = members[ 1 ]-hier_id.
    IF hierarchy = zzxxmla1_cl_mdx_schema_reader=>c_measures.
      RETURN.
    ENDIF.
    DATA(context) = evaluator->get_members( ).
    IF measures_conflict( context ) = abap_true.
      RETURN.
    ENDIF.
    DATA filters TYPE zzxxmla1_cl_mdx_facts=>ty_t_filter.
    DATA(own) = VALUE ty_member( ).
    LOOP AT context INTO DATA(member) WHERE hier_id <> zzxxmla1_cl_mdx_schema_reader=>c_measures.
      IF member-unique_name = schema_reader->get_default_member( member-hier_id )-unique_name.
        CONTINUE.
      ENDIF.
      IF member-calculated = abap_true OR member-is_null = abap_true.
        RETURN.
      ENDIF.
      IF member-key_level = 0.
        CONTINUE.
      ENDIF.
      IF member-hier_id = hierarchy.
        own = member.
      ELSE.
        APPEND VALUE #( hierarchy = member-hier_id level = member-key_level path = member-path ) TO filters.
      ENDIF.
    ENDLOOP.

    CLEAR result.
    DATA(key_level) = -1.
    DATA paths TYPE ty_path_set.
    LOOP AT members INTO member.
      IF member-hier_id <> hierarchy OR member-calculated = abap_true OR member-key_level = 0.
        " not read from the facts
        APPEND member TO result.
        CONTINUE.
      ENDIF.
      IF member-key_level <> key_level.
        key_level = member-key_level.
        paths = context_paths( filters = filters hierarchy = hierarchy key_level = key_level ).
      ENDIF.
      IF line_exists( paths[ table_line = member-path ] )
          AND ( own IS INITIAL OR on_one_path( path1 = own-path path2 = member-path ) = abap_true ).
        APPEND member TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD context_paths.
    DATA(all) = filters.
    APPEND VALUE #( hierarchy = hierarchy level = key_level any = abap_true ) TO all.
    DATA(key) = ``.
    LOOP AT all INTO DATA(filter).
      key = |{ key }{ filter-hierarchy }:{ filter-level }:{ filter-any }:{ filter-path };|.
    ENDLOOP.
    ASSIGN context_paths_cache[ key = key ] TO FIELD-SYMBOL(<cached>).
    IF sy-subrc = 0.
      result = <cached>-paths.
      RETURN.
    ENDIF.
    LOOP AT fact_reader->non_empty_paths( all ) INTO DATA(paths).
      INSERT paths[ 1 ] INTO TABLE result.
    ENDLOOP.
    INSERT VALUE #( key = key paths = result ) INTO TABLE context_paths_cache.
  ENDMETHOD.

  METHOD on_one_path.
    DATA(length1) = strlen( path1 ).
    DATA(length2) = strlen( path2 ).
    IF length1 = length2.
      result = xsdbool( path1 = path2 ).
    ELSEIF length1 < length2.
      result = xsdbool( substring( val = path2 len = length1 ) = path1
                        AND substring( val = path2 off = length1 len = 1 ) = zzxxmla1_cl_model=>c_separator ).
    ELSE.
      result = xsdbool( substring( val = path1 len = length2 ) = path2
                        AND substring( val = path1 off = length2 len = 1 ) = zzxxmla1_cl_model=>c_separator ).
    ENDIF.
  ENDMETHOD.

  METHOD type_hierarchies.
    DATA(element) = type->strip_set_type( ).
    IF element IS NOT BOUND.
      RETURN.
    ENDIF.
    DATA(types) = COND zzxxmla1_cl_mdx_type=>ty_t_type( WHEN element->kind = zzxxmla1_cl_mdx_type=>c_kind-tuple
                                                         THEN element->element_types ELSE VALUE #( ( element ) ) ).
    LOOP AT types INTO DATA(member_type).
      DATA(hierarchy) = member_type->get_hierarchy( ).
      IF hierarchy <> zzxxmla1_cl_mdx_type=>c_none.
        APPEND schema_reader->get_hierarchy( hierarchy )-unique_name TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD load_special_members.
    LOOP AT evaluator->get_members( ) INTO DATA(member)
         WHERE calculated = abap_false AND hier_id <> zzxxmla1_cl_mdx_schema_reader=>c_measures AND key_level > 0.
      DATA(hierarchy) = schema_reader->get_hierarchy( member-hier_id ).
      IF schema_reader->get_dimension( hierarchy-dimension )-type <> `TimeDimension`
          AND hierarchy-has_all = abap_false.
        APPEND schema_reader->get_hierarchy_root_members( member-hier_id ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD replace_non_all_members.
    LOOP AT lists ASSIGNING FIELD-SYMBOL(<list>).
      DATA(hierarchy) = <list>[ 1 ]-hier_id.
      DATA(found) = VALUE ty_t_member( FOR member IN members WHERE ( hier_id = hierarchy ) ( member ) ).
      IF found IS NOT INITIAL.
        <list> = found.
        result = abap_true.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD top_members.
    LOOP AT tuples INTO DATA(tuple).
      LOOP AT tuple INTO DATA(member)
           WHERE hier_id <> zzxxmla1_cl_mdx_schema_reader=>c_measures AND calculated = abap_false AND key_level > 0.
        DATA(top) = member.
        DO.
          DATA(parent) = schema_reader->get_parent_member( top ).
          IF parent IS INITIAL OR parent-key_level = 0.
            EXIT.
          ENDIF.
          top = parent.
        ENDDO.
        IF NOT line_exists( result[ unique_name = top-unique_name ] ).
          APPEND top TO result.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD eval_execute.
    IF index = 0.
      result = execute_axis( evaluator = evaluator expression = expression non_empty = non_empty ).
      RETURN.
    ENDIF.
    " executeAxis marks the axis ordered if its set is an Order call; a NON EMPTY axis' set is a NonEmpty call
    DATA(ordered) = xsdbool( expression->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call
                             AND to_upper( expression->fun_def-name ) = `ORDER` AND non_empty = abap_false ).
    DATA(savepoint) = evaluator->savepoint( ).
    LOOP AT lists[ index ] INTO DATA(member).
      evaluator->set_context( member ).
      result = merge_axes( axis1   = result
                           axis2   = eval_execute( evaluator = evaluator lists = lists index = index - 1
                                                   expression = expression non_empty = non_empty )
                           ordered = ordered ).
    ENDLOOP.
    evaluator->restore( savepoint ).
  ENDMETHOD.

  METHOD merge_axes.
    IF axis1 IS INITIAL.
      result = axis2.
      RETURN.
    ENDIF.
    DATA seen TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    DATA(half_way) = 0.
    DO 2 TIMES.
      DATA(axis) = COND ty_t_tuple( WHEN sy-index = 1 THEN axis1 ELSE axis2 ).
      LOOP AT axis INTO DATA(tuple).
        INSERT tuple_key( tuple ) INTO TABLE seen.
        IF sy-subrc = 0.
          APPEND tuple TO result.
        ENDIF.
      ENDLOOP.
      IF half_way = 0.
        half_way = lines( result ).
      ENDIF.
    ENDDO.
    IF half_way > 0 AND half_way < lines( result ) AND ordered = abap_false.
      result = hierarchize( result ).
    ENDIF.
  ENDMETHOD.

  METHOD last_dimension.
    result = -1.
    IF node IS NOT BOUND.
      RETURN.
    ENDIF.
    CASE node->kind.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-dimension.
        result = node->element-id.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-hierarchy.
        result = schema_reader->dimension_of( node->element-id ).
      WHEN zzxxmla1_cl_mdx_node=>c_kind-member.
        result = schema_reader->dimension_of( node->element-member-hier_id ).
      WHEN zzxxmla1_cl_mdx_node=>c_kind-named_set.
        result = last_dimension( node->set_expression ).
      WHEN OTHERS.
        LOOP AT node->args INTO DATA(arg).
          DATA(dimension) = last_dimension( arg ).
          IF dimension >= 0.
            result = dimension.
          ENDIF.
        ENDLOOP.
    ENDCASE.
  ENDMETHOD.

  METHOD execute_stripe.
    DATA(savepoint) = evaluator->savepoint( ).
    IF axis_index = 0.
      evaluator->set_context_members( slicer ).
      DATA(cell) = compute_cell( evaluator ).
      cell-ordinal = lines( cells ).
      APPEND cell TO cells.
    ELSE.
      " a savepoint per tuple, as the reference (the stack decides the context stack of an infinite loop)
      LOOP AT axes[ axis_index ]-tuples INTO DATA(tuple).
        DATA(tuple_savepoint) = evaluator->savepoint( ).
        evaluator->set_eval_axes( abap_true ).
        evaluator->set_context_members( tuple ).
        execute_stripe( EXPORTING evaluator = evaluator axes = axes slicer = slicer axis_index = axis_index - 1
                        CHANGING  cells = cells ).
        evaluator->restore( tuple_savepoint ).
      ENDLOOP.
    ENDIF.
    evaluator->restore( savepoint ).
  ENDMETHOD.

  METHOD remove_empty_positions.
    " the cell of position p of the axis has the coordinate (ordinal DIV stride) MOD size, stride being the product of
    " the sizes of the axes before it
    DATA keep TYPE STANDARD TABLE OF abap_bool WITH EMPTY KEY.
    DATA(stride) = 1.
    DATA(before) = position - 1.
    LOOP AT result-axes INTO DATA(axis) TO before.
      stride = stride * lines( axis-tuples ).
    ENDLOOP.
    DATA(size) = lines( result-axes[ position ]-tuples ).
    keep = VALUE #( FOR i = 1 UNTIL i > size ( abap_false ) ).
    LOOP AT result-cells INTO DATA(cell) WHERE empty = abap_false.
      keep[ ( cell-ordinal DIV stride ) MOD size + 1 ] = abap_true.
    ENDLOOP.

    DATA(tuples) = VALUE ty_t_tuple( ).
    LOOP AT result-axes[ position ]-tuples INTO DATA(tuple).
      IF keep[ sy-tabix ] = abap_true.
        APPEND tuple TO tuples.
      ENDIF.
    ENDLOOP.
    result-axes[ position ]-tuples = tuples.

    DATA(cells) = VALUE ty_t_cell( ).
    LOOP AT result-cells INTO cell.
      IF keep[ ( cell-ordinal DIV stride ) MOD size + 1 ] = abap_true.
        cell-ordinal = lines( cells ).
        APPEND cell TO cells.
      ENDIF.
    ENDLOOP.
    result-cells = cells.
  ENDMETHOD.

  METHOD key_of.
    result = |{ to_upper( node->fun_def-name ) }\|{ node->fun_def-syntax }\||
          && concat_lines_of( table = VALUE string_table( FOR category IN node->fun_def-signature_categories
                                                          ( |{ category }| ) ) sep = `,` ).
  ENDMETHOD.

  METHOD not_implemented.
    fail( |The evaluation of { COND #( WHEN node->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call
                                       THEN node->fun_def-signature ELSE node->unparse( ) ) } is not implemented yet| ).
  ENDMETHOD.

  METHOD evaluate_set.
    IF node->kind = zzxxmla1_cl_mdx_node=>c_kind-named_set.
      result = named_set_tuples( evaluator = evaluator node = node ).
      RETURN.
    ENDIF.
    IF node->kind <> zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
      " a member or tuple where a set is wanted
      result = VALUE #( ( evaluate_tuple( evaluator = evaluator node = node ) ) ).
      RETURN.
    ENDIF.

    CASE node->fun_def-implementation.
      WHEN `SetFunDef`.
        " the members, tuples and sets of the braces in turn
        LOOP AT node->args INTO DATA(arg).
          CASE node->fun_def-parameter_categories[ sy-tabix ].
            WHEN c_category-member.
              APPEND VALUE #( ( evaluate_member( evaluator = evaluator node = arg ) ) ) TO result.
            WHEN c_category-tuple.
              APPEND evaluate_tuple( evaluator = evaluator node = arg ) TO result.
            WHEN OTHERS.
              APPEND LINES OF evaluate_set( evaluator = evaluator node = arg ) TO result.
          ENDCASE.
        ENDLOOP.
        without_null_tuples( CHANGING tuples = result ).
        RETURN.
      WHEN `ParenthesesFunDef`.
        result = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
        RETURN.
      WHEN `TupleFunDef`.
        result = VALUE #( ( evaluate_tuple( evaluator = evaluator node = node ) ) ).
        RETURN.
      WHEN `NonEmptyCrossJoinFunDef`.
        result = non_empty_crossjoin( evaluator = evaluator node = node ).
        RETURN.
      WHEN `CrossJoinFunDef`.
        " CrossJoinFunDef: natively while the evaluator is non-empty, if the arguments allow
        DATA native TYPE abap_bool.
        result = native_crossjoin( EXPORTING evaluator = evaluator node = node IMPORTING native = native ).
        IF native = abap_true.
          RETURN.
        ENDIF.
        result = evaluate_arg_as_set( evaluator = evaluator call = node index = 1 ).
        LOOP AT node->args INTO arg FROM 2.
          result = cross_join( left = result
                               right = evaluate_arg_as_set( evaluator = evaluator call = node index = sy-tabix ) ).
        ENDLOOP.
        RETURN.
      WHEN `OrderFunDef`.
        result = order( evaluator = evaluator node = node ).
        RETURN.
      WHEN `AsFunDef`.
        " a dynamic named set: evaluated anew each time
        result = named_set_tuples( evaluator = evaluator node = node->args[ 2 ] anew = abap_true ).
        RETURN.
    ENDCASE.
    " TopBottomCountFunDef (a MultiResolver: the signature has the categories of the arguments)
    IF node->fun_def-name = `TopCount` OR node->fun_def-name = `BottomCount`.
      result = top_bottom_count( evaluator = evaluator node = node top = xsdbool( node->fun_def-name = `TopCount` ) ).
      RETURN.
    ENDIF.
    IF node->fun_def-name = `Descendants`.
      result = descendants( evaluator = evaluator node = node ).
      RETURN.
    ENDIF.
    IF to_upper( node->fun_def-name ) = `PARAMETER`.
      " ParameterFunDef: no value is set, so the default
      result = evaluate_set( evaluator = evaluator node = node->args[ 3 ] ).
      RETURN.
    ENDIF.

    DATA(key) = key_of( node ).
    CASE key.
      WHEN `MEMBERS|Property|3`.
        DATA(hierarchy) = evaluate_hierarchy( evaluator = evaluator node = node->args[ 1 ] ).
        IF evaluator->is_non_empty( ) = abap_true AND hierarchy <> zzxxmla1_cl_mdx_schema_reader=>c_measures.
          " FunUtil.hierarchyMembers: the non-empty members of each level, hierarchized
          DATA(members) = VALUE ty_t_member( ).
          LOOP AT schema_reader->get_hierarchy( hierarchy )-levels INTO DATA(level).
            APPEND LINES OF non_empty_level_members( evaluator = evaluator level = level ) TO members.
          ENDLOOP.
          SORT members BY ordinal ASCENDING.
          result = VALUE #( FOR member IN members ( VALUE #( ( member ) ) ) ).
        ELSE.
          result = VALUE #( FOR member IN schema_reader->get_hierarchy_members( hierarchy ) ( VALUE #( ( member ) ) ) ).
        ENDIF.
      WHEN `ALLMEMBERS|Property|3`.
        " with the calculated members
        hierarchy = evaluate_hierarchy( evaluator = evaluator node = node->args[ 1 ] ).
        result = members_with_calculated( evaluator = evaluator levels = schema_reader->get_hierarchy( hierarchy )-levels ).
      WHEN `MEMBERS|Property|4`.
        result = VALUE #( FOR member IN non_empty_level_members(
                                          evaluator = evaluator
                                          level     = evaluate_level( evaluator = evaluator node = node->args[ 1 ] ) )
                          ( VALUE #( ( member ) ) ) ).
      WHEN `ALLMEMBERS|Property|4`.
        result = members_with_calculated(
                   evaluator = evaluator
                   levels    = VALUE #( ( evaluate_level( evaluator = evaluator node = node->args[ 1 ] ) ) ) ).
      WHEN `CHILDREN|Property|6`.
        DATA(parent) = evaluate_member( evaluator = evaluator node = node->args[ 1 ] ).
        result = VALUE #( FOR member IN non_empty_children( evaluator = evaluator member = parent )
                          ( VALUE #( ( member ) ) ) ).
      WHEN `NATIVIZESET|Function|8`.
        " NativizeSetFunDef: below NativizeMinThreshold (100,000) the set itself; native evaluation gives the same tuples
        result = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
      WHEN `HIERARCHIZE|Function|8`.
        result = hierarchize( evaluate_set( evaluator = evaluator node = node->args[ 1 ] ) ).
      WHEN `HIERARCHIZE|Function|8,11`.
        IF node->args[ 2 ]->value <> `PRE`.
          not_implemented( node ).
        ENDIF.
        result = hierarchize( evaluate_set( evaluator = evaluator node = node->args[ 1 ] ) ).
      WHEN `DRILLDOWNLEVELTOP|Function|8,7` OR `DRILLDOWNLEVELTOP|Function|8,7,4`
        OR `DRILLDOWNLEVELTOP|Function|8,7,4,7` OR `DRILLDOWNLEVELTOP|Function|8,7,17,7`.
        result = drill_down_level_top( evaluator = evaluator node = node ).
      WHEN `FILTER|Function|8,5`.
        result = filter( evaluator = evaluator node = node ).
      WHEN `:|Infix|6,6`.
        result = range( evaluator = evaluator node = node ).
      WHEN `UNION|Function|8,8` OR `UNION|Function|8,8,11`.
        result = union( evaluator = evaluator node = node ).
      WHEN `EXCEPT|Function|8,8` OR `EXCEPT|Function|8,8,11` OR `-|Infix|8,8`.
        " <Set> - <Set> is compiled as Except
        result = except( evaluator = evaluator node = node ).
      WHEN `-|Prefix|8`.
        " The reference compiles - <Set> as the set itself
        result = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
      WHEN `INTERSECT|Function|8,8` OR `INTERSECT|Function|8,8,11`.
        result = intersect( evaluator = evaluator node = node ).
      WHEN `HEAD|Function|8` OR `HEAD|Function|8,7`.
        result = head_tail( evaluator = evaluator node = node head = abap_true ).
      WHEN `TAIL|Function|8` OR `TAIL|Function|8,7`.
        result = head_tail( evaluator = evaluator node = node head = abap_false ).
      WHEN `SIBLINGS|Property|6`.
        result = VALUE #( FOR sibling IN siblings_of( evaluate_member( evaluator = evaluator node = node->args[ 1 ] ) )
                          ( VALUE #( ( sibling ) ) ) ).
      WHEN `ANCESTORS|Function|6,4` OR `ANCESTORS|Function|6,7`.
        result = ancestors( evaluator = evaluator node = node ).
      WHEN `ASCENDANTS|Function|6`.
        " the member and its ancestors; none for the null member
        DATA(ascendant) = evaluate_member( evaluator = evaluator node = node->args[ 1 ] ).
        WHILE ascendant IS NOT INITIAL AND ascendant-is_null = abap_false.
          APPEND VALUE #( ( ascendant ) ) TO result.
          ascendant = schema_reader->get_parent_member( ascendant ).
        ENDWHILE.
      WHEN `PERIODSTODATE|Function|` OR `PERIODSTODATE|Function|4` OR `PERIODSTODATE|Function|4,6`.
        result = periods_to_date( evaluator = evaluator node = node ).
      WHEN `YTD|Function|` OR `YTD|Function|6` OR `QTD|Function|` OR `QTD|Function|6` OR `MTD|Function|`
        OR `MTD|Function|6` OR `WTD|Function|` OR `WTD|Function|6`.
        result = xtd( evaluator = evaluator node = node ).
      WHEN `SUBSET|Function|8,7` OR `SUBSET|Function|8,7,7`.
        result = subset( evaluator = evaluator node = node ).
      WHEN `GENERATE|Function|8,8` OR `GENERATE|Function|8,8,11`.
        result = generate( evaluator = evaluator node = node ).
      WHEN `DISTINCT|Function|8`.
        result = distinct( evaluate_set( evaluator = evaluator node = node->args[ 1 ] ) ).
      WHEN `EXISTING|Prefix|8`.
        result = existing( evaluator = evaluator node = node ).
      WHEN `VISUALTOTALS|Function|8` OR `VISUALTOTALS|Function|8,9`.
        result = visual_totals( evaluator = evaluator node = node ).
      WHEN `ADDCALCULATEDMEMBERS|Function|8`.
        result = add_calculated_members( evaluate_set( evaluator = evaluator node = node->args[ 1 ] ) ).
      WHEN `DRILLDOWNLEVEL|Function|8` OR `DRILLDOWNLEVEL|Function|8,4` OR `DRILLDOWNLEVEL|Function|8,17,7`
        OR `DRILLDOWNLEVEL|Function|8,4,11` OR `DRILLDOWNLEVEL|Function|8,17,7,11`
        OR `DRILLDOWNLEVEL|Function|8,17,17,11`.
        result = drilldown_level( evaluator = evaluator node = node ).
      WHEN `DRILLDOWNMEMBER|Function|8,8` OR `DRILLDOWNMEMBER|Function|8,8,11` OR `DRILLDOWNMEMBER|Function|8,8,17,17,11`.
        result = drilldown_member( evaluator = evaluator node = node ).
      WHEN `EXISTS|Function|8,8`.
        result = exists( evaluator = evaluator node = node ).
      WHEN OTHERS.
        not_implemented( node ).
    ENDCASE.
  ENDMETHOD.

  METHOD evaluate_arg_as_set.
    DATA(arg) = call->args[ index ].
    IF arg->get_type( )->is_set( ) = abap_true.
      result = evaluate_set( evaluator = evaluator node = arg ).
    ELSE.
      " * and () take members and tuples too
      result = VALUE #( ( evaluate_tuple( evaluator = evaluator node = arg ) ) ).
    ENDIF.
  ENDMETHOD.

  METHOD evaluate_tuple.
    IF node->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call AND node->fun_def-implementation = `TupleFunDef`.
      LOOP AT node->args INTO DATA(arg).
        APPEND evaluate_member( evaluator = evaluator node = arg ) TO result.
      ENDLOOP.
    ELSEIF node->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call
        AND node->fun_def-implementation = `ParenthesesFunDef`.
      result = evaluate_tuple( evaluator = evaluator node = node->args[ 1 ] ).
    ELSEIF node->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call
        AND node->fun_def-implementation = `SetItemFunDef`.
      result = set_item( evaluator = evaluator node = node ).
    ELSEIF node->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call
        AND to_upper( node->fun_def-name ) = `CURRENT` AND node->fun_def-syntax = zzxxmla1_cl_mdx_node=>c_syntax-property.
      result = named_set_current( evaluator = evaluator node = node ).
    ELSE.
      result = VALUE #( ( evaluate_member( evaluator = evaluator node = node ) ) ).
    ENDIF.
  ENDMETHOD.

  METHOD evaluate_member.
    CASE node->kind.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-member.
        result = node->element-member.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-hierarchy OR zzxxmla1_cl_mdx_node=>c_kind-dimension.
        " the current member of the (default) hierarchy
        result = current_member( evaluator = evaluator hierarchy = evaluate_hierarchy( evaluator = evaluator
                                                                                       node = node ) ).
      WHEN zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
        IF node->fun_def-implementation = `ParenthesesFunDef`.
          result = evaluate_member( evaluator = evaluator node = node->args[ 1 ] ).
          RETURN.
        ELSEIF node->fun_def-implementation = `SetItemFunDef`.
          DATA(item) = set_item( evaluator = evaluator node = node ).
          result = item[ 1 ].
          RETURN.
        ENDIF.
        CASE key_of( node ).
          WHEN `CURRENTMEMBER|Property|3`.
            result = current_member( evaluator = evaluator
                                     hierarchy = evaluate_hierarchy( evaluator = evaluator node = node->args[ 1 ] ) ).
          WHEN `DEFAULTMEMBER|Property|3`.
            result = schema_reader->get_default_member( evaluate_hierarchy( evaluator = evaluator
                                                                             node = node->args[ 1 ] ) ).
          WHEN `ITEM|Method|10,7`.
            result = tuple_item( evaluator = evaluator node = node ).
          WHEN `CURRENT|Property|8`.
            DATA(current) = named_set_current( evaluator = evaluator node = node ).
            result = current[ 1 ].
          WHEN `PARENT|Property|6` OR `FIRSTCHILD|Property|6` OR `LASTCHILD|Property|6` OR `FIRSTSIBLING|Property|6`
            OR `LASTSIBLING|Property|6` OR `NEXTMEMBER|Property|6` OR `PREVMEMBER|Property|6` OR `LAG|Method|6,7`
            OR `LEAD|Method|6,7`.
            result = navigate( evaluator = evaluator node = node ).
          WHEN `ANCESTOR|Function|6,4`.
            " AncestorFunDef: the level, then the member; the distance is the difference of their depths
            DATA(ancestor_level) = evaluate_level( evaluator = evaluator node = node->args[ 2 ] ).
            DATA(descendant) = evaluate_member( evaluator = evaluator node = node->args[ 1 ] ).
            result = ancestor( member = descendant
                               distance = depth_of( descendant ) - schema_reader->get_level( ancestor_level )-depth
                               level = ancestor_level ).
          WHEN `ANCESTOR|Function|6,7`.
            " compileInteger: a number truncated
            DATA(distance) = CONV i( trunc( evaluate_number( evaluator = evaluator node = node->args[ 2 ] ) ) ).
            result = ancestor( member = evaluate_member( evaluator = evaluator node = node->args[ 1 ] )
                               distance = distance ).
          WHEN `CALCULATEDCHILD|Method|6,9`.
            DATA(child_name) = evaluate_string( evaluator = evaluator node = node->args[ 2 ] ).
            result = calculated_child( member = evaluate_member( evaluator = evaluator node = node->args[ 1 ] )
                                       name = child_name-text ).
          WHEN `CURRENTDATEMEMBER|Function|3,9` OR `CURRENTDATEMEMBER|Function|3,9,11`.
            result = current_date_member( evaluator = evaluator node = node ).
          WHEN `LASTNONEMPTY|Function|8,6`.
            result = last_non_empty( evaluator = evaluator node = node ).
          WHEN `COUSIN|Function|6,6`.
            result = cousin( member = evaluate_member( evaluator = evaluator node = node->args[ 1 ] )
                             ancestor = evaluate_member( evaluator = evaluator node = node->args[ 2 ] ) ).
          WHEN `PARALLELPERIOD|Function|` OR `PARALLELPERIOD|Function|4` OR `PARALLELPERIOD|Function|4,7`
            OR `PARALLELPERIOD|Function|4,7,6`.
            result = parallel_period( evaluator = evaluator node = node ).
          WHEN `OPENINGPERIOD|Function|` OR `OPENINGPERIOD|Function|4` OR `OPENINGPERIOD|Function|4,6`
            OR `CLOSINGPERIOD|Function|` OR `CLOSINGPERIOD|Function|4` OR `CLOSINGPERIOD|Function|4,6`
            OR `CLOSINGPERIOD|Function|6`.
            result = opening_closing_period( evaluator = evaluator node = node ).
          WHEN OTHERS.
            IF to_upper( node->fun_def-name ) = `PARAMETER`.
              " ParameterFunDef: no value is set, so the default
              result = evaluate_member( evaluator = evaluator node = node->args[ 3 ] ).
              RETURN.
            ENDIF.
            not_implemented( node ).
        ENDCASE.
      WHEN OTHERS.
        not_implemented( node ).
    ENDCASE.
  ENDMETHOD.

  METHOD evaluate_hierarchy.
    CASE node->kind.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-hierarchy.
        result = node->element-id.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-dimension.
        DATA(dimension) = schema_reader->get_dimension( node->element-id ).
        result = dimension-hierarchies[ 1 ].
      WHEN zzxxmla1_cl_mdx_node=>c_kind-level.
        result = schema_reader->get_level( node->element-id )-hierarchy.
      WHEN OTHERS.
        IF node->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
          CASE key_of( node ).
            WHEN `HIERARCHY|Property|6`.
              result = evaluate_member( evaluator = evaluator node = node->args[ 1 ] )-hier_id.
              RETURN.
            WHEN `HIERARCHY|Property|4`.
              result = schema_reader->get_level( evaluate_level( evaluator = evaluator node = node->args[ 1 ] ) )-hierarchy.
              RETURN.
          ENDCASE.
        ENDIF.
        result = evaluate_member( evaluator = evaluator node = node )-hier_id.
    ENDCASE.
  ENDMETHOD.

  METHOD evaluate_level.
    IF node->kind = zzxxmla1_cl_mdx_node=>c_kind-level.
      result = node->element-id.
      RETURN.
    ENDIF.
    IF node->kind <> zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
      not_implemented( node ).
    ENDIF.
    CASE key_of( node ).
      WHEN `LEVEL|Property|6`.
        result = evaluate_member( evaluator = evaluator node = node->args[ 1 ] )-level.
      WHEN `LEVELS|Method|3,7`.
        " the level at the position, the (All) level being 0
        DATA(hierarchy) = schema_reader->get_hierarchy( evaluate_hierarchy( evaluator = evaluator node = node->args[ 1 ] ) ).
        DATA(value) = evaluate_double( evaluator = evaluator node = node->args[ 2 ] ).
        " compileInteger: null is IntegerNull (Integer.MIN_VALUE + 1)
        DATA(ordinal) = COND i( WHEN value-empty = abap_true THEN -2147483647 ELSE trunc( value-number ) ).
        IF ordinal < 0 OR ordinal >= lines( hierarchy-levels ).
          zzxxmla1_cx_mdx_evaluation=>raise_error( |Index '{ ordinal }' out of bounds| ).
        ENDIF.
        result = hierarchy-levels[ ordinal + 1 ].
      WHEN `LEVELS|Method|3,9`.
        " the level with the name (case-sensitive)
        hierarchy = schema_reader->get_hierarchy( evaluate_hierarchy( evaluator = evaluator node = node->args[ 1 ] ) ).
        DATA(name) = evaluate_string( evaluator = evaluator node = node->args[ 2 ] )-text.
        LOOP AT hierarchy-levels INTO DATA(level).
          IF schema_reader->get_level( level )-name = name.
            result = level.
            RETURN.
          ENDIF.
        ENDLOOP.
        zzxxmla1_cx_mdx_evaluation=>raise_error(
          |Level '{ name }' not found in hierarchy '{ hierarchy-unique_name }'| ).
      WHEN OTHERS.
        not_implemented( node ).
    ENDCASE.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_calc~evaluate.
    result = evaluate_value( evaluator = evaluator node = node ).
  ENDMETHOD.

  METHOD evaluate_value.
    IF node->kind = zzxxmla1_cl_mdx_node=>c_kind-literal.
      CASE node->category.
        WHEN zzxxmla1_cl_mdx_node=>c_category-numeric.
          result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-numeric number = node->number ).
        WHEN zzxxmla1_cl_mdx_node=>c_category-string.
          result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string text = node->value ).
        WHEN zzxxmla1_cl_mdx_node=>c_category-null.
          result-empty = abap_true.
        WHEN OTHERS.
          not_implemented( node ).
      ENDCASE.
      RETURN.
    ENDIF.
    IF node->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call
        AND node->fun_def-implementation = `ParenthesesFunDef`.
      result = evaluate_value( evaluator = evaluator node = node->args[ 1 ] ).
      RETURN.
    ENDIF.
    " a tuple of members (MemberArrayValueCalc): after a savepoint each member is evaluated and set in turn, a null
    " member makes the value null
    IF node->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call AND node->fun_def-implementation = `TupleFunDef`
        AND node->get_type( )->kind = zzxxmla1_cl_mdx_type=>c_kind-tuple.
      DATA(tuple_savepoint) = evaluator->savepoint( ).
      TRY.
          LOOP AT node->args INTO DATA(arg).
            DATA(element) = evaluate_member( evaluator = evaluator node = arg ).
            IF element-is_null = abap_true OR element IS INITIAL.
              result-empty = abap_true.
              EXIT.
            ENDIF.
            evaluator->set_context( element ).
          ENDLOOP.
          IF result-empty = abap_false.
            result = evaluator->evaluate_current( ).
          ENDIF.
        CLEANUP.
          evaluator->restore( tuple_savepoint ).
      ENDTRY.
      evaluator->restore( tuple_savepoint ).
      RETURN.
    ENDIF.
    " a member or tuple: the cell of the context with it
    DATA(tuple) = VALUE ty_tuple( ).
    CASE node->get_type( )->kind.
      WHEN zzxxmla1_cl_mdx_type=>c_kind-member OR zzxxmla1_cl_mdx_type=>c_kind-hierarchy
          OR zzxxmla1_cl_mdx_type=>c_kind-dimension.
        tuple = VALUE #( ( evaluate_member( evaluator = evaluator node = node ) ) ).
      WHEN zzxxmla1_cl_mdx_type=>c_kind-tuple.
        tuple = evaluate_tuple( evaluator = evaluator node = node ).
      WHEN OTHERS.
        IF node->kind <> zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
          not_implemented( node ).
        ENDIF.
        result = evaluate_scalar_call( evaluator = evaluator node = node ).
        RETURN.
    ENDCASE.
    " MemberValueCalc, MemberArrayValueCalc: a null member makes the value null, nothing is evaluated
    IF line_exists( tuple[ is_null = abap_true ] ).
      result-empty = abap_true.
      RETURN.
    ENDIF.
    DATA(savepoint) = evaluator->savepoint( ).
    evaluator->set_context_members( tuple ).
    result = evaluator->evaluate_current( ).
    evaluator->restore( savepoint ).
  ENDMETHOD.

  METHOD evaluate_scalar_call.
    CASE node->fun_def-implementation.
      WHEN `CastFunDef`.
        result = cast( evaluator = evaluator node = node ).
        RETURN.
      WHEN `CoalesceEmptyFunDef`.
        " the first value that is not null
        LOOP AT node->args INTO DATA(coalesced).
          result = evaluate_value( evaluator = evaluator node = coalesced ).
          IF result-empty = abap_false.
            RETURN.
          ENDIF.
        ENDLOOP.
        RETURN.
      WHEN `CaseTestFunDef` OR `CaseMatchFunDef`.
        result = case( evaluator = evaluator node = node ).
        RETURN.
      WHEN `PropertiesFunDef`.
        DATA(property) = evaluate_string( evaluator = evaluator node = node->args[ 2 ] ).
        result = member_property( member = evaluate_member( evaluator = evaluator node = node->args[ 1 ] )
                                  name = property-text ).
        RETURN.
    ENDCASE.
    " the operators of BuiltinFunTable; null (DoubleNull) is the identity of + and -, and makes * and / null
    CASE key_of( node ).
      WHEN `AGGREGATE|Function|8` OR `AGGREGATE|Function|8,7`.
        result = aggregate( evaluator = evaluator node = node ).
      WHEN `COUNT|Function|8` OR `COUNT|Function|8,11` OR `COUNT|Property|8`.
        result = count( evaluator = evaluator node = node ).
      WHEN `SUM|Function|8` OR `SUM|Function|8,7` OR `AVG|Function|8` OR `AVG|Function|8,7`
        OR `MIN|Function|8` OR `MIN|Function|8,7` OR `MAX|Function|8` OR `MAX|Function|8,7`.
        result = set_aggregate( evaluator = evaluator node = node ).
      WHEN `RANK|Function|10,8` OR `RANK|Function|10,8,7` OR `RANK|Function|6,8` OR `RANK|Function|6,8,7`.
        result = rank( evaluator = evaluator node = node ).
      WHEN `MOD|Function|13,13`.
        result = modulo( evaluator = evaluator node = node ).
      WHEN `CINT|Function|13`.
        result = java_cint( evaluate_value( evaluator = evaluator node = node->args[ 1 ] ) ).
      WHEN `FORMAT|Function|6,9` OR `FORMAT|Function|7,9` OR `FORMAT|Function|18,9`.
        result = format( evaluator = evaluator node = node ).
      WHEN `SETTOSTR|Function|8`.
        result = set_to_str( evaluator = evaluator node = node ).
      WHEN `GENERATE|Function|8,9` OR `GENERATE|Function|8,9,9` OR `GENERATE|Function|8,7,9`.
        result = generate_string( evaluator = evaluator node = node ).
      WHEN `CURRENTORDINAL|Property|8`.
        " the named set is evaluated if it is not yet
        named_set_tuples( evaluator = evaluator node = node->args[ 1 ] ).
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer
                          number = named_set_values[ key = node->args[ 1 ]->set_key ]-ordinal ).
      WHEN `+|Infix|7,7` OR `-|Infix|7,7`.
        DATA(left) = evaluate_double( evaluator = evaluator node = node->args[ 1 ] ).
        DATA(right) = evaluate_double( evaluator = evaluator node = node->args[ 2 ] ).
        DATA(sign) = COND f( WHEN node->fun_def-name = `+` THEN 1 ELSE -1 ).
        IF left-empty = abap_true AND right-empty = abap_true.
          result-empty = abap_true.
        ELSEIF left-empty = abap_true.
          result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-numeric number = sign * right-number ).
        ELSEIF right-empty = abap_true.
          result = left.
        ELSE.
          result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-numeric
                            number = left-number + sign * right-number ).
        ENDIF.
      WHEN `*|Infix|7,7`.
        left = evaluate_double( evaluator = evaluator node = node->args[ 1 ] ).
        right = evaluate_double( evaluator = evaluator node = node->args[ 2 ] ).
        IF left-empty = abap_true OR right-empty = abap_true.
          result-empty = abap_true.
        ELSE.
          result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-numeric number = left-number * right-number ).
        ENDIF.
      WHEN `/|Infix|7,7`.
        " NullDenominatorProducesNull is false: a null numerator is null, a null denominator gives Infinity
        left = evaluate_double( evaluator = evaluator node = node->args[ 1 ] ).
        right = evaluate_double( evaluator = evaluator node = node->args[ 2 ] ).
        IF left-empty = abap_true.
          result-empty = abap_true.
        ELSEIF right-empty = abap_true.
          result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-numeric special = `INF` ).
        ELSE.
          result = divide( dividend = left-number divisor = right-number ).
        ENDIF.
      WHEN `-|Prefix|7`.
        result = evaluate_double( evaluator = evaluator node = node->args[ 1 ] ).
        IF result-empty = abap_false.
          result-number = - result-number.
        ENDIF.
      WHEN `=|Infix|5,5` OR `=|Infix|7,7` OR `=|Infix|9,9` OR `<>|Infix|5,5` OR `<>|Infix|7,7` OR `<>|Infix|9,9`
        OR `<|Infix|7,7` OR `<|Infix|9,9` OR `<=|Infix|7,7` OR `<=|Infix|9,9` OR `>|Infix|7,7` OR `>|Infix|9,9`
        OR `>=|Infix|7,7` OR `>=|Infix|9,9`.
        result = logical( compare( evaluator = evaluator node = node ) ).
      WHEN `AND|Infix|5,5`.
        " both are evaluated while the axes are, else the second only if the first is true
        DATA(first) = evaluate_boolean( evaluator = evaluator node = node->args[ 1 ] ).
        IF first = abap_false AND evaluator->is_eval_axes( ) = abap_false.
          result = logical( abap_false ).
        ELSE.
          result = logical( xsdbool( evaluate_boolean( evaluator = evaluator node = node->args[ 2 ] ) = abap_true
                                     AND first = abap_true ) ).
        ENDIF.
      WHEN `OR|Infix|5,5`.
        first = evaluate_boolean( evaluator = evaluator node = node->args[ 1 ] ).
        IF first = abap_true AND evaluator->is_eval_axes( ) = abap_false.
          result = logical( abap_true ).
        ELSE.
          result = logical( xsdbool( evaluate_boolean( evaluator = evaluator node = node->args[ 2 ] ) = abap_true
                                     OR first = abap_true ) ).
        ENDIF.
      WHEN `XOR|Infix|5,5`.
        first = evaluate_boolean( evaluator = evaluator node = node->args[ 1 ] ).
        result = logical( xsdbool( evaluate_boolean( evaluator = evaluator node = node->args[ 2 ] ) <> first ) ).
      WHEN `NOT|Prefix|5`.
        result = logical( xsdbool( evaluate_boolean( evaluator = evaluator node = node->args[ 1 ] ) = abap_false ) ).
      WHEN `ISEMPTY|Function|9` OR `ISEMPTY|Function|7` OR `IS EMPTY|Postfix|6` OR `IS EMPTY|Postfix|10`.
        " IsEmptyFunDef: the value is null (DoubleNull); <Member or Tuple> IS EMPTY the cell of the context with it
        result = logical( evaluate_value( evaluator = evaluator node = node->args[ 1 ] )-empty ).
      WHEN `IS|Infix|6,6` OR `IS|Infix|4,4` OR `IS|Infix|3,3` OR `IS|Infix|2,2` OR `IS|Infix|10,10`.
        result = logical( is_same( evaluator = evaluator node = node ) ).
      WHEN `IS NULL|Postfix|6` OR `IS NULL|Postfix|3` OR `IS NULL|Postfix|2`.
        " IsNullFunDef: the null member (no member has a null key here)
        result = logical( evaluate_member( evaluator = evaluator node = node->args[ 1 ] )-is_null ).
      WHEN `IN|Infix|6,8`.
        result = logical( member_in_set( evaluator = evaluator node = node ) ).
      WHEN `MATCHES|Infix|9,9`.
        result = logical( string_matches( evaluator = evaluator node = node ) ).
      WHEN `IIF|Function|5,5,5` OR `IIF|Function|5,7,7` OR `IIF|Function|5,9,9`.
        DATA(chosen) = COND #( WHEN evaluate_boolean( evaluator = evaluator node = node->args[ 1 ] ) = abap_true
                               THEN node->args[ 2 ] ELSE node->args[ 3 ] ).
        result = evaluate_value( evaluator = evaluator node = chosen ).
      WHEN `|||Infix|9,9`.
        " Java's concatenation: null is the text null
        DATA(left_text) = evaluate_string( evaluator = evaluator node = node->args[ 1 ] ).
        DATA(right_text) = evaluate_string( evaluator = evaluator node = node->args[ 2 ] ).
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string
                          text = zzxxmla1_cl_mdx_evaluator=>to_text( left_text )
                              && zzxxmla1_cl_mdx_evaluator=>to_text( right_text ) ).
      WHEN `LEN|Function|9`.
        " the number of characters; null is 0
        DATA(text) = evaluate_string( evaluator = evaluator node = node->args[ 1 ] ).
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer number = strlen( text-text ) ).
      WHEN `STRING|Function|15,9`.
        " Vba.string: the first character of the text, repeated
        DATA(count) = CONV i( trunc( evaluate_number( evaluator = evaluator node = node->args[ 1 ] ) ) ).
        text = evaluate_string( evaluator = evaluator node = node->args[ 2 ] ).
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string ).
        IF text-text IS NOT INITIAL.
          result-text = repeat( val = substring( val = text-text len = 1 ) occ = count ).
        ENDIF.
      WHEN `MID|Function|9,15` OR `MID|Function|9,15,15`.
        " Vba.mid: the characters from the 1-based start, as many as the length (default: all)
        text = evaluate_string( evaluator = evaluator node = node->args[ 1 ] ).
        DATA(start) = CONV i( trunc( evaluate_number( evaluator = evaluator node = node->args[ 2 ] ) ) ).
        DATA(length) = COND i( WHEN lines( node->args ) = 3
                               THEN trunc( evaluate_number( evaluator = evaluator node = node->args[ 3 ] ) )
                               ELSE strlen( text-text ) ).
        IF start <= 0.
          fail( `Invalid parameter. Start parameter of Mid function must be positive` ).
        ELSEIF length < 0.
          fail( `Invalid parameter. Length parameter of Mid function must be non-negative` ).
        ENDIF.
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string ).
        IF start <= strlen( text-text ).
          result-text = substring( val = text-text off = start - 1
                                   len = nmin( val1 = length val2 = strlen( text-text ) - start + 1 ) ).
        ENDIF.
      WHEN `NAME|Property|6`.
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string
                          text = name_of( evaluate_member( evaluator = evaluator node = node->args[ 1 ] ) ) ).
      WHEN `CAPTION|Property|6`.
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string
                          text = evaluate_member( evaluator = evaluator node = node->args[ 1 ] )-caption ).
      WHEN `UNIQUENAME|Property|6` OR `UNIQUE_NAME|Property|6`.
        " Unique_Name is the reference's synonym of <Member>.UniqueName (BuiltinFunTable)
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string
                          text = evaluate_member( evaluator = evaluator node = node->args[ 1 ] )-unique_name ).
      WHEN `UNIQUENAME|Property|4` OR `NAME|Property|4` OR `CAPTION|Property|4`.
        DATA(level) = schema_reader->get_level( evaluate_level( evaluator = evaluator node = node->args[ 1 ] ) ).
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string
                          text = COND #( WHEN node->fun_def-name = `UniqueName` THEN level-unique_name
                                         ELSE level-name ) ).
      WHEN `UNIQUENAME|Property|3` OR `NAME|Property|3` OR `CAPTION|Property|3`.
        DATA(hierarchy) = schema_reader->get_hierarchy( evaluate_hierarchy( evaluator = evaluator
                                                                            node = node->args[ 1 ] ) ).
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string
                          text = COND #( WHEN node->fun_def-name = `UniqueName` THEN hierarchy-unique_name
                                         ELSE hierarchy-name ) ).
      WHEN `UNIQUENAME|Property|2` OR `NAME|Property|2` OR `CAPTION|Property|2`.
        DATA(dimension) = schema_reader->get_dimension( evaluate_dimension( evaluator = evaluator
                                                                            node = node->args[ 1 ] ) ).
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string
                          text = COND #( WHEN node->fun_def-name = `UniqueName` THEN dimension-unique_name
                                         ELSE dimension-name ) ).
      WHEN `ORDINAL|Property|4`.
        " the depth of the level
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer
                          number = schema_reader->get_level( evaluate_level( evaluator = evaluator
                                                                              node = node->args[ 1 ] ) )-depth ).
      WHEN `ORDERKEY|Property|6`.
        " MemberOrderKeyFunDef: an OrderKey of the member
        DATA(ordered) = evaluate_member( evaluator = evaluator node = node->args[ 1 ] ).
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-order_key member = ordered text = ordered-key ).
      WHEN OTHERS.
        IF to_upper( node->fun_def-name ) = `PARAMETER`
            AND ( node->get_type( )->kind = zzxxmla1_cl_mdx_type=>c_kind-string
               OR node->get_type( )->kind = zzxxmla1_cl_mdx_type=>c_kind-numeric ).
          " Parameter(name, type, default[, description]): no value is set, so the default
          result = evaluate_value( evaluator = evaluator node = node->args[ 3 ] ).
          RETURN.
        ENDIF.
        not_implemented( node ).
    ENDCASE.
  ENDMETHOD.

  METHOD evaluate_string.
    result = evaluate_value( evaluator = evaluator node = node ).
    IF result-empty = abap_false AND result-kind <> zzxxmla1_cl_mdx_evaluator=>c_value-string.
      result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string
                        text = zzxxmla1_cl_mdx_evaluator=>to_text( result ) ).
    ENDIF.
  ENDMETHOD.

  METHOD evaluate_boolean.
    DATA(value) = evaluate_value( evaluator = evaluator node = node ).
    IF value-empty = abap_true.
      RETURN.
    ENDIF.
    CASE value-kind.
      WHEN zzxxmla1_cl_mdx_evaluator=>c_value-logical.
        result = value-boolean.
      WHEN zzxxmla1_cl_mdx_evaluator=>c_value-numeric OR zzxxmla1_cl_mdx_evaluator=>c_value-integer.
        result = xsdbool( value-number <> 0 OR value-special IS NOT INITIAL ).
    ENDCASE.
  ENDMETHOD.

  METHOD compare.
    " the largest double (cl_abap_math=>max_float is not in 7.50)
    CONSTANTS c_max_float TYPE f VALUE '1.7976931348623157E+308'.
    DATA(name) = node->fun_def-name.
    DATA(order) = 0.
    CASE node->fun_def-signature_categories[ 1 ].
      WHEN c_category-logical.
        DATA(first) = evaluate_boolean( evaluator = evaluator node = node->args[ 1 ] ).
        DATA(second) = evaluate_boolean( evaluator = evaluator node = node->args[ 2 ] ).
        result = xsdbool( ( name = `=` AND first = second ) OR ( name = `<>` AND first <> second ) ).
        RETURN.
      WHEN c_category-string.
        DATA(left_text) = evaluate_string( evaluator = evaluator node = node->args[ 1 ] ).
        DATA(right_text) = evaluate_string( evaluator = evaluator node = node->args[ 2 ] ).
        IF left_text-empty = abap_true OR right_text-empty = abap_true.
          RETURN.
        ENDIF.
        order = COND #( WHEN left_text-text < right_text-text THEN -1 WHEN left_text-text > right_text-text THEN 1 ).
      WHEN OTHERS.
        DATA(left) = evaluate_double( evaluator = evaluator node = node->args[ 1 ] ).
        DATA(right) = evaluate_double( evaluator = evaluator node = node->args[ 2 ] ).
        IF left-empty = abap_true OR right-empty = abap_true OR left-special = `NAN` OR right-special = `NAN`.
          RETURN.
        ENDIF.
        " infinities compare beyond every number
        DATA(left_number) = COND f( WHEN left-special = `INF` THEN c_max_float
                                    WHEN left-special = `-INF` THEN - c_max_float
                                    ELSE left-number ).
        DATA(right_number) = COND f( WHEN right-special = `INF` THEN c_max_float
                                     WHEN right-special = `-INF` THEN - c_max_float
                                     ELSE right-number ).
        order = COND #( WHEN left_number < right_number THEN -1 WHEN left_number > right_number THEN 1 ).
    ENDCASE.
    result = SWITCH #( name WHEN `=` THEN xsdbool( order = 0 ) WHEN `<>` THEN xsdbool( order <> 0 )
                            WHEN `<` THEN xsdbool( order < 0 ) WHEN `<=` THEN xsdbool( order <= 0 )
                            WHEN `>` THEN xsdbool( order > 0 ) WHEN `>=` THEN xsdbool( order >= 0 ) ).
  ENDMETHOD.

  METHOD logical.
    result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-logical boolean = value ).
  ENDMETHOD.

  METHOD evaluate_double.
    result = evaluate_value( evaluator = evaluator node = node ).
    IF result-empty = abap_true.
      RETURN.
    ENDIF.
    CASE result-kind.
      WHEN zzxxmla1_cl_mdx_evaluator=>c_value-integer.
        result-kind = zzxxmla1_cl_mdx_evaluator=>c_value-numeric.
      WHEN zzxxmla1_cl_mdx_evaluator=>c_value-string OR zzxxmla1_cl_mdx_evaluator=>c_value-logical.
        " GenericCalc.evaluateDouble: the value is no Number
        DATA(error) = type_error( expected = `NUMERIC` value = result ).
        RAISE EXCEPTION error.
    ENDCASE.
  ENDMETHOD.

  METHOD divide.
    result-kind = zzxxmla1_cl_mdx_evaluator=>c_value-numeric.
    IF divisor = 0.
      result-special = COND #( WHEN dividend > 0 THEN `INF` WHEN dividend < 0 THEN `-INF` ELSE `NAN` ).
    ELSE.
      result-number = dividend / divisor.
    ENDIF.
  ENDMETHOD.

  METHOD members_with_calculated.
    LOOP AT levels INTO DATA(level).
      LOOP AT non_empty_level_members( evaluator = evaluator level = level ) INTO DATA(member).
        APPEND VALUE #( ( member ) ) TO result.
      ENDLOOP.
      LOOP AT schema_reader->get_calculated_members( schema_reader->get_level( level )-hierarchy )
           INTO member WHERE level = level.
        APPEND VALUE #( ( member ) ) TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD evaluate_number.
    result = evaluate_double( evaluator = evaluator node = node )-number.
  ENDMETHOD.

  METHOD cross_join.
    " CrossJoinFunDef: each list, then the crossjoin, before it is built
    check_result_limit( CONV #( lines( left ) ) ).
    check_result_limit( CONV #( lines( right ) ) ).
    check_result_limit( CONV decfloat34( lines( left ) ) * lines( right ) ).
    LOOP AT left INTO DATA(left_tuple).
      LOOP AT right INTO DATA(right_tuple).
        DATA(tuple) = left_tuple.
        APPEND LINES OF right_tuple TO tuple.
        APPEND tuple TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_result_limit.
    CONSTANTS c_max_int TYPE i VALUE 2147483647.
    IF result_limit > 0 AND size > result_limit.
      execute_error( |Size of CrossJoin result ({ group_digits( size ) }) exceeded limit ({ group_digits( CONV #( result_limit ) ) })| ).
    ENDIF.
    IF size > c_max_int.
      execute_error( |Size of CrossJoin result ({ group_digits( size ) }) exceeded limit ({ group_digits( CONV #( c_max_int ) ) })| ).
    ENDIF.
  ENDMETHOD.

  METHOD group_digits.
    DATA(digits) = |{ number DECIMALS = 0 }|.
    WHILE strlen( digits ) > 3.
      result = |,{ substring( val = digits off = strlen( digits ) - 3 ) }{ result }|.
      digits = substring( val = digits len = strlen( digits ) - 3 ).
    ENDWHILE.
    result = digits && result.
  ENDMETHOD.

  METHOD hierarchize.
    " parents before their children, the members of a level in hierarchy order; tuples by their members in turn
    TYPES:
      BEGIN OF ty_keyed,
        key   TYPE string,
        tuple TYPE ty_tuple,
      END OF ty_keyed.
    DATA keyed TYPE STANDARD TABLE OF ty_keyed WITH EMPTY KEY.
    DATA(path) = abap_false.
    LOOP AT tuples INTO DATA(tuple).
      IF line_exists( tuple[ calculated = abap_true ] ).
        path = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    LOOP AT tuples INTO tuple.
      " a tab after each member: an ancestor's key is a prefix of its descendants' and sorts first
      DATA(key) = VALUE string( ).
      LOOP AT tuple INTO DATA(member).
        key = key && hierarchize_key( member = member path = path ) && cl_abap_char_utilities=>horizontal_tab.
      ENDLOOP.
      APPEND VALUE #( key = key tuple = tuple ) TO keyed.
    ENDLOOP.
    SORT keyed STABLE BY key ASCENDING.
    result = VALUE #( FOR row IN keyed ( row-tuple ) ).
  ENDMETHOD.

  METHOD hierarchize_key.
    DATA(current) = member.
    DO.
      result = COND #( WHEN current-calculated = abap_true
                       THEN |1{ current-ordinal WIDTH = 10 ALIGN = RIGHT PAD = '0' }{ current-caption }|
                       ELSE |0{ current-ordinal WIDTH = 10 ALIGN = RIGHT PAD = '0' }| ) && result.
      IF path = abap_false.
        RETURN.
      ENDIF.
      current = schema_reader->get_parent_member( current ).
      IF current IS INITIAL.
        RETURN.
      ENDIF.
    ENDDO.
  ENDMETHOD.

  METHOD non_empty_list.
    " The reference checks the measures of the query; the stored measures of a cube are empty in the same cells, so the
    " measure of the context answers for them
    DATA(savepoint) = evaluator->savepoint( ).
    LOOP AT tuples INTO DATA(tuple).
      evaluator->set_context_members( tuple ).
      IF evaluator->evaluate_current( )-empty = abap_false.
        APPEND tuple TO result.
      ENDIF.
      evaluator->restore( savepoint ).
    ENDLOOP.
  ENDMETHOD.

  METHOD drill_down_level_top.
    " DrillDownLevelTop(set, count [, level [, value]]): after each member (of the level, if one is given) come its top
    " count children by the value (the cell of the context if none is given); empty values rank last
    TYPES:
      BEGIN OF ty_ranked,
        filled TYPE abap_bool,
        amount TYPE f,
        member TYPE ty_member,
      END OF ty_ranked.
    DATA ranked TYPE STANDARD TABLE OF ty_ranked WITH EMPTY KEY.
    DATA(tuples) = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
    DATA(count) = CONV i( evaluate_number( evaluator = evaluator node = node->args[ 2 ] ) ).
    IF count <= 0.
      result = tuples.
      RETURN.
    ENDIF.
    DATA(level) = -1.
    IF lines( node->args ) > 2 AND node->fun_def-signature_categories[ 3 ] = c_category-level.
      level = evaluate_level( evaluator = evaluator node = node->args[ 3 ] ).
    ENDIF.

    LOOP AT tuples INTO DATA(tuple).
      DATA(member) = tuple[ 1 ].
      APPEND tuple TO result.
      IF level >= 0 AND member-level <> level.
        IF schema_reader->dimension_of( schema_reader->get_level( level )-hierarchy )
            <> schema_reader->dimension_of( member-hier_id ).
          fail( |Level '{ schema_reader->get_level( level )-unique_name }' not compatible with member '|
                && |{ member-unique_name }'| ).
        ENDIF.
        CONTINUE.
      ENDIF.
      DATA(savepoint) = evaluator->savepoint( ).
      evaluator->set_non_empty( abap_false ).
      CLEAR ranked.
      LOOP AT schema_reader->get_member_children( member ) INTO DATA(child).
        evaluator->set_context( child ).
        DATA(value) = COND #( WHEN lines( node->args ) = 4 THEN evaluate_value( evaluator = evaluator
                                                                                node = node->args[ 4 ] )
                              ELSE evaluator->evaluate_current( ) ).
        APPEND VALUE #( filled = xsdbool( value-empty = abap_false ) amount = value-number member = child ) TO ranked.
      ENDLOOP.
      evaluator->restore( savepoint ).
      SORT ranked STABLE BY filled DESCENDING amount DESCENDING.
      LOOP AT ranked INTO DATA(rank) TO count.
        APPEND VALUE #( ( rank-member ) ) TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD filter.
    " the list calcs (MutableListCalc, ImmutableListCalc) and the iterable ones evaluate the same way: the set in the
    " context of the call, then the condition per tuple, non-empty off; the context is restored afterwards
    DATA(tuples) = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
    DATA(savepoint) = evaluator->savepoint( ).
    evaluator->set_non_empty( abap_false ).
    TRY.
        LOOP AT tuples INTO DATA(tuple).
          set_position( node = node->args[ 1 ] index = sy-tabix ).
          evaluator->set_context_members( tuple ).
          IF evaluate_boolean( evaluator = evaluator node = node->args[ 2 ] ) = abap_true.
            APPEND tuple TO result.
          ENDIF.
        ENDLOOP.
      CLEANUP.
        evaluator->restore( savepoint ).
    ENDTRY.
    evaluator->restore( savepoint ).
  ENDMETHOD.

  METHOD top_bottom_count.
    " the count is an integer (compileInteger: a number truncated, null is 0); 0 gives the empty set
    DATA(count) = CONV i( trunc( evaluate_number( evaluator = evaluator node = node->args[ 2 ] ) ) ).
    IF count <= 0.
      RETURN.
    ENDIF.
    result = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
    IF lines( node->args ) < 3.
      IF top = abap_true.
        DELETE result FROM count + 1.
      ELSEIF lines( result ) > count.
        DELETE result TO lines( result ) - count.
      ENDIF.
      RETURN.
    ENDIF.
    IF lines( result ) <= 1.
      RETURN.
    ENDIF.
    " the comparators of Order's BDESC / BASC (BreakMemberComparator, BreakTupleComparator); no ContextCalc and the
    " non-empty flag as it is
    DATA(keys) = VALUE ty_t_sort_key( ( expression = node->args[ 3 ] descending = top brk = abap_true ) ).
    DATA(savepoint) = evaluator->savepoint( ).
    sort_run = sort_run + 1.
    DATA(run) = sort_run.
    TRY.
        sort_tuples( EXPORTING evaluator = evaluator keys = keys run = run CHANGING tuples = result ).
      CLEANUP.
        DELETE sort_values WHERE run = run.
        evaluator->restore( savepoint ).
    ENDTRY.
    DELETE sort_values WHERE run = run.
    evaluator->restore( savepoint ).
    DELETE result FROM count + 1.
  ENDMETHOD.

  METHOD range.
    " SmartMemberReader.getMemberRange: the start, then its next members in the level (also across parents) to the
    " end; empty if the end comes first, then FunUtil.memberRange tries the members the other way round
    DATA(member0) = evaluate_member( evaluator = evaluator node = node->args[ 1 ] ).
    DATA(member1) = evaluate_member( evaluator = evaluator node = node->args[ 2 ] ).
    IF member0-level <> member1-level.
      zzxxmla1_cx_mdx_evaluation=>raise_error( `Members must belong to the same level` ).
    ENDIF.
    DATA(first) = nmin( val1 = member0-ordinal val2 = member1-ordinal ).
    DATA(last) = nmax( val1 = member0-ordinal val2 = member1-ordinal ).
    LOOP AT schema_reader->get_level_members( member0-level ) INTO DATA(member)
         WHERE ordinal >= first AND ordinal <= last.
      APPEND VALUE #( ( member ) ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD descendants.
    DATA(set_type) = node->args[ 1 ]->get_type( ).
    IF set_type->is_set( ) = abap_false.
      result = VALUE #( FOR member IN descendants_of_member( evaluator = evaluator node = node
                                                             member = evaluate_member( evaluator = evaluator
                                                                                       node = node->args[ 1 ] ) )
                        ( VALUE #( ( member ) ) ) ).
      RETURN.
    ENDIF.
    IF set_type->get_arity( ) > 1.
      fail( `Argument to Descendants function must be a member or set of members, not a set of tuples` ).
    ENDIF.
    " GenerateFunDef without ALL: each member of the set as the context in turn, a descendant only the first time
    DATA seen TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    DATA(tuples) = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
    DATA(savepoint) = evaluator->savepoint( ).
    TRY.
        LOOP AT tuples INTO DATA(tuple).
          evaluator->set_context_members( tuple ).
          LOOP AT descendants_of_member( evaluator = evaluator node = node member = tuple[ 1 ] ) INTO DATA(descendant).
            INSERT descendant-unique_name INTO TABLE seen.
            IF sy-subrc = 0.
              APPEND VALUE #( ( descendant ) ) TO result.
            ENDIF.
          ENDLOOP.
        ENDLOOP.
      CLEANUP.
        evaluator->restore( savepoint ).
    ENDTRY.
    evaluator->restore( savepoint ).
  ENDMETHOD.

  METHOD descendants_of_member.
    DATA(count) = lines( node->args ).
    " SELF without a flag, SELF_BEFORE_AFTER with the member only
    DATA(flag) = COND string( WHEN count = 1 THEN `SELF_BEFORE_AFTER` ELSE `SELF` ).
    IF count >= 3.
      flag = to_upper( node->args[ 3 ]->value ).
    ENDIF.
    DATA(self) = xsdbool( flag CS `SELF` ).
    DATA(before) = xsdbool( flag CS `BEFORE` ).
    DATA(after) = xsdbool( flag CS `AFTER` ).
    DATA(leaves) = xsdbool( flag = `LEAVES` ).
    DATA(kind) = COND string( WHEN count >= 2 THEN node->args[ 2 ]->get_type( )->kind ).
    DATA(depth_specified) = xsdbool( kind = zzxxmla1_cl_mdx_type=>c_kind-numeric
                                     OR kind = zzxxmla1_cl_mdx_type=>c_kind-decimal ).
    DATA(depth_empty) = xsdbool( kind = zzxxmla1_cl_mdx_type=>c_kind-empty ).
    IF depth_empty = abap_true AND leaves = abap_false.
      fail( `depth must be specified unless DESC_FLAG is LEAVES` ).
    ENDIF.
    " compileInteger: a number truncated, null is IntegerNull (Integer.MIN_VALUE + 1)
    DATA(depth) = 0.
    IF depth_specified = abap_true.
      DATA(value) = evaluate_double( evaluator = evaluator node = node->args[ 2 ] ).
      depth = COND #( WHEN value-empty = abap_true THEN -2147483647 ELSE trunc( value-number ) ).
    ENDIF.

    IF ( depth_specified = abap_true OR depth_empty = abap_true ) AND leaves = abap_true.
      result = descendants_leaves_by_depth( member = member
                                            depth_limit = COND #( WHEN depth_specified = abap_true AND depth >= 0
                                                                  THEN depth ELSE -1 ) ).
    ELSEIF depth_specified = abap_true.
      result = descendants_by_depth( evaluator = evaluator member = member depth_limit = depth
                                     before = before self = self after = after ).
    ELSE.
      " the evaluator is the context of the children (the non-empty ones under a non-empty evaluator)
      DATA(level) = COND i( WHEN count > 1 THEN evaluate_level( evaluator = evaluator node = node->args[ 2 ] )
                            ELSE member-level ).
      result = descendants_by_level( evaluator = evaluator ancestor = member level = level
                                     before = before self = self after = after leaves = leaves ).
    ENDIF.
    " hierarchizeMemberList( result, false ): pre-order
    SORT result BY ordinal ASCENDING.
  ENDMETHOD.

  METHOD descendants_by_depth.
    DATA(children) = VALUE ty_t_member( ( member ) ).
    DATA(depth) = 0.
    DO.
      IF depth = depth_limit.
        IF self = abap_true.
          APPEND LINES OF children TO result.
        ENDIF.
        IF after = abap_false.
          EXIT.
        ENDIF.
      ELSEIF depth < depth_limit.
        IF before = abap_true.
          APPEND LINES OF children TO result.
        ENDIF.
      ELSE.
        IF after = abap_false.
          EXIT.
        ENDIF.
        APPEND LINES OF children TO result.
      ENDIF.
      DATA(next_members) = VALUE ty_t_member( ).
      LOOP AT children INTO DATA(child).
        APPEND LINES OF schema_reader->get_member_children( child ) TO next_members.
      ENDLOOP.
      " getMemberChildren( children, context ): the non-empty ones under a non-empty evaluator
      next_members = context_members( evaluator = evaluator members = next_members ).
      IF next_members IS INITIAL.
        EXIT.
      ENDIF.
      children = next_members.
      depth = depth + 1.
    ENDDO.
  ENDMETHOD.

  METHOD descendants_leaves_by_depth.
    IF is_drillable( member ) = abap_false.
      IF depth_limit >= 0.
        APPEND member TO result.
      ENDIF.
      RETURN.
    ENDIF.
    DATA(children) = VALUE ty_t_member( ( member ) ).
    DATA(depth) = 0.
    WHILE depth_limit = -1 OR depth <= depth_limit.
      DATA(next_members) = VALUE ty_t_member( ).
      LOOP AT children INTO DATA(parent).
        APPEND LINES OF schema_reader->get_member_children( parent ) TO next_members.
      ENDLOOP.
      children = VALUE #( ).
      LOOP AT next_members INTO DATA(child).
        IF is_drillable( child ) = abap_true.
          APPEND child TO children.
        ELSE.
          APPEND child TO result.
        ENDIF.
      ENDLOOP.
      IF children IS INITIAL.
        RETURN.
      ENDIF.
      depth = depth + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD descendants_by_level.
    DATA(level_depth) = schema_reader->get_level( level )-depth.
    DATA(members) = VALUE ty_t_member( ( ancestor ) ).
    IF leaves = abap_true.
      WHILE members IS NOT INITIAL.
        DATA(next_members) = VALUE ty_t_member( ).
        LOOP AT members INTO DATA(member).
          DATA(current_depth) = depth_of( member ).
          IF current_depth = level_depth.
            APPEND member TO result.
          ELSE.
            DATA(children) = non_empty_children( evaluator = evaluator member = member ).
            IF children IS INITIAL.
              IF current_depth <= level_depth.
                APPEND member TO result.
              ENDIF.
            ELSEIF current_depth <= level_depth.
              APPEND LINES OF children TO next_members.
            ENDIF.
          ENDIF.
        ENDLOOP.
        members = next_members.
      ENDWHILE.
      RETURN.
    ENDIF.
    WHILE members IS NOT INITIAL.
      DATA(fertile) = VALUE ty_t_member( ).
      LOOP AT members INTO member.
        current_depth = depth_of( member ).
        IF current_depth = level_depth.
          IF self = abap_true.
            APPEND member TO result.
          ENDIF.
          IF after = abap_true.
            APPEND member TO fertile.
          ENDIF.
        ELSEIF current_depth < level_depth.
          IF before = abap_true.
            APPEND member TO result.
          ENDIF.
          APPEND member TO fertile.
        ELSEIF after = abap_true.
          APPEND member TO result.
          APPEND member TO fertile.
        ENDIF.
      ENDLOOP.
      members = VALUE #( ).
      LOOP AT fertile INTO member.
        APPEND LINES OF schema_reader->get_member_children( member ) TO members.
      ENDLOOP.
      members = context_members( evaluator = evaluator members = members ).
    ENDWHILE.
  ENDMETHOD.

  METHOD is_drillable.
    DATA(level) = schema_reader->get_level( member-level ).
    result = xsdbool( level-depth < lines( schema_reader->get_hierarchy( level-hierarchy )-levels ) - 1 ).
  ENDMETHOD.

  METHOD depth_of.
    result = schema_reader->get_level( member-level )-depth.
  ENDMETHOD.

  METHOD order.
    " buildKeySpecList: each key a value, then the symbol of its direction (ASC if there is none)
    DATA keys TYPE ty_t_sort_key.
    DATA(j) = 2.
    WHILE j <= lines( node->args ).
      DATA(key) = VALUE ty_sort_key( expression = node->args[ j ] ).
      j = j + 1.
      IF j <= lines( node->args ) AND node->args[ j ]->kind = zzxxmla1_cl_mdx_node=>c_kind-literal
          AND node->args[ j ]->category = zzxxmla1_cl_mdx_node=>c_category-symbol.
        DATA(flag) = to_upper( node->args[ j ]->value ).
        IF flag <> `ASC` AND flag <> `DESC` AND flag <> `BASC` AND flag <> `BDESC`.
          " FunDefBase.getLiteralArg
          compile_error( `Allowed values are: {ASC, DESC, BASC, BDESC}` ).
        ENDIF.
        key-descending = xsdbool( flag = `DESC` OR flag = `BDESC` ).
        key-brk = xsdbool( flag = `BASC` OR flag = `BDESC` ).
        j = j + 1.
      ENDIF.
      APPEND key TO keys.
    ENDWHILE.

    result = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
    IF lines( result ) <= 1.
      RETURN.
    ENDIF.
    DATA(savepoint) = evaluator->savepoint( ).
    " compileCall: one key that is a member or tuple (MemberValueCalc, MemberArrayValueCalc) whose members are constant
    " and not used by the set: they are set as the context (ContextCalc) and the key is the cell of the context
    " (ValueCalc), or the one member that is not constant; with more such members nothing is set
    IF lines( keys ) = 1.
      DATA(expression) = keys[ 1 ]-expression.
      DATA(parts) = COND zzxxmla1_cl_mdx_node=>ty_t_node(
        WHEN expression->kind = zzxxmla1_cl_mdx_node=>c_kind-member THEN VALUE #( ( expression ) )
        WHEN expression->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call
             AND expression->fun_def-implementation = `TupleFunDef` THEN expression->args ).
      DATA constants TYPE ty_tuple.
      DATA variables TYPE zzxxmla1_cl_mdx_node=>ty_t_node.
      LOOP AT parts INTO DATA(part).
        IF part->kind = zzxxmla1_cl_mdx_node=>c_kind-member
            AND depends_on( node = node->args[ 1 ] hierarchy = part->element-member-hier_id
                            as_value = abap_false ) = abap_false.
          APPEND part->element-member TO constants.
        ELSE.
          APPEND part TO variables.
        ENDIF.
      ENDLOOP.
      IF constants IS NOT INITIAL AND lines( variables ) <= 1.
        evaluator->set_context_members( constants ).
        keys[ 1 ]-expression = COND #( WHEN variables IS NOT INITIAL THEN variables[ 1 ] ).
      ENDIF.
    ENDIF.
    evaluator->set_non_empty( abap_false ).
    sort_run = sort_run + 1.
    DATA(run) = sort_run.
    TRY.
        " Sorter evaluates the keys in the order of the set (preloadValues): the position of a named set is the tuple's
        DATA(set) = node->args[ 1 ].
        IF set->kind = zzxxmla1_cl_mdx_node=>c_kind-named_set
            OR ( set->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call AND set->fun_def-implementation = `AsFunDef` ).
          LOOP AT result INTO DATA(preloaded).
            set_position( node = set index = sy-tabix ).
            LOOP AT keys INTO key.
              DATA(preload_index) = sy-tabix.
              sort_value( evaluator = evaluator key = key key_index = preload_index run = run
                          members = COND #( WHEN lines( preloaded ) = 1 THEN preloaded
                                            ELSE dependent_members( key = key tuple = preloaded ) ) ).
            ENDLOOP.
          ENDLOOP.
        ENDIF.
        sort_tuples( EXPORTING evaluator = evaluator keys = keys run = run CHANGING tuples = result ).
      CLEANUP.
        DELETE sort_values WHERE run = run.
        evaluator->restore( savepoint ).
    ENDTRY.
    DELETE sort_values WHERE run = run.
    evaluator->restore( savepoint ).
  ENDMETHOD.

  METHOD sort_tuples.
    " bottom-up merge sort: stable, as Java sorts lists and arrays of objects
    DATA source TYPE ty_t_tuple.
    DATA(count) = lines( tuples ).
    DATA(width) = 1.
    WHILE width < count.
      source = tuples.
      CLEAR tuples.
      DATA(left) = 1.
      WHILE left <= count.
        DATA(middle) = nmin( val1 = left + width val2 = count + 1 ).
        DATA(right) = nmin( val1 = left + 2 * width val2 = count + 1 ).
        DATA(i) = left.
        DATA(k) = middle.
        WHILE i < middle OR k < right.
          DATA(take_left) = abap_false.
          IF k >= right.
            take_left = abap_true.
          ELSEIF i < middle.
            take_left = xsdbool( compare_by_keys( evaluator = evaluator keys = keys run = run
                                                  tuple1 = source[ i ] tuple2 = source[ k ] ) <= 0 ).
          ENDIF.
          IF take_left = abap_true.
            APPEND source[ i ] TO tuples.
            i = i + 1.
          ELSE.
            APPEND source[ k ] TO tuples.
            k = k + 1.
          ENDIF.
        ENDWHILE.
        left = right.
      ENDWHILE.
      width = width * 2.
    ENDWHILE.
  ENDMETHOD.

  METHOD compare_by_keys.
    DATA(key_index) = 0.
    LOOP AT keys INTO DATA(key).
      key_index = key_index + 1.
      result = compare_by_key( evaluator = evaluator key = key key_index = key_index run = run
                               tuple1 = tuple1 tuple2 = tuple2 ).
      IF result <> 0.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD compare_by_key.
    IF lines( tuple1 ) = 1.
      " Sorter.sortMembers
      IF key-brk = abap_true.
        result = compare_values(
          value1 = sort_value( evaluator = evaluator key = key key_index = key_index run = run members = tuple1 )
          value2 = sort_value( evaluator = evaluator key = key key_index = key_index run = run members = tuple2 ) ).
        result = COND #( WHEN key-descending = abap_true THEN - result ELSE result ).
      ELSE.
        result = compare_hierarchically( evaluator = evaluator key = key key_index = key_index run = run
                                         member1 = tuple1[ 1 ] member2 = tuple2[ 1 ] in_tuple = abap_false ).
      ENDIF.
      RETURN.
    ENDIF.

    " Sorter.sortTuples (TupleExpMemoComparator): only the members the key depends on count, and equal ones compare
    " as 0 before anything is evaluated
    DATA(members1) = dependent_members( key = key tuple = tuple1 ).
    DATA(members2) = dependent_members( key = key tuple = tuple2 ).
    DATA(equal) = abap_true.
    LOOP AT members1 INTO DATA(member1).
      IF member1-unique_name <> members2[ sy-tabix ]-unique_name.
        equal = abap_false.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF equal = abap_true.
      RETURN.
    ENDIF.
    IF key-brk = abap_true.
      result = compare_values(
        value1 = sort_value( evaluator = evaluator key = key key_index = key_index run = run members = members1 )
        value2 = sort_value( evaluator = evaluator key = key key_index = key_index run = run members = members2 ) ).
      result = COND #( WHEN key-descending = abap_true THEN - result ELSE result ).
      RETURN.
    ENDIF.
    " HierarchicalTupleComparator: member by member, the equal ones before set as the context
    DATA(savepoint) = evaluator->savepoint( ).
    LOOP AT members1 INTO member1.
      DATA(member2) = members2[ sy-tabix ].
      result = compare_hierarchically( evaluator = evaluator key = key key_index = key_index run = run
                                       member1 = member1 member2 = member2 in_tuple = abap_true ).
      IF result <> 0.
        EXIT.
      ENDIF.
      evaluator->set_context( member1 ).
    ENDLOOP.
    evaluator->restore( savepoint ).
  ENDMETHOD.

  METHOD sort_value.
    DATA(name) = concat_lines_of( table = VALUE string_table( FOR member IN members ( member-unique_name ) ) sep = `,` ).
    READ TABLE sort_values INTO DATA(known) WITH TABLE KEY run = run key = key_index name = name.
    IF sy-subrc = 0.
      result = known-value.
      RETURN.
    ENDIF.
    DATA(savepoint) = evaluator->savepoint( ).
    evaluator->set_context_members( members ).
    result = evaluate_key( evaluator = evaluator key = key ).
    evaluator->restore( savepoint ).
    INSERT VALUE #( run = run key = key_index name = name value = result ) INTO TABLE sort_values.
  ENDMETHOD.

  METHOD compare_hierarchically.
    IF member1-unique_name = member2-unique_name.
      RETURN.
    ENDIF.
    DATA(m1) = member1.
    DATA(m2) = member2.
    DO.
      IF m1-level_number < m2-level_number.
        m2 = schema_reader->get_parent_member( m2 ).
        IF m1-unique_name = m2-unique_name.
          result = -1.
          RETURN.
        ENDIF.
      ELSEIF m1-level_number > m2-level_number.
        m1 = schema_reader->get_parent_member( m1 ).
        IF m1-unique_name = m2-unique_name.
          result = 1.
          RETURN.
        ENDIF.
      ELSE.
        DATA(previous1) = m1.
        DATA(previous2) = m2.
        m1 = schema_reader->get_parent_member( m1 ).
        m2 = schema_reader->get_parent_member( m2 ).
        IF m1-unique_name = m2-unique_name.
          " siblings, or both without a parent
          IF in_tuple = abap_true.
            DATA(savepoint) = evaluator->savepoint( ).
            evaluator->set_context( previous1 ).
            DATA(value1) = evaluate_key( evaluator = evaluator key = key ).
            evaluator->set_context( previous2 ).
            DATA(value2) = evaluate_key( evaluator = evaluator key = key ).
            evaluator->restore( savepoint ).
            result = compare_values( value1 = value1 value2 = value2 ).
            IF result = 0.
              result = compare_siblings( member1 = previous1 member2 = previous2 ).
            ENDIF.
            result = COND #( WHEN key-descending = abap_true THEN - result ELSE result ).
          ELSE.
            result = compare_values(
              value1 = sort_value( evaluator = evaluator key = key key_index = key_index run = run
                                   members = VALUE #( ( previous1 ) ) )
              value2 = sort_value( evaluator = evaluator key = key key_index = key_index run = run
                                   members = VALUE #( ( previous2 ) ) ) ).
            result = COND #( WHEN key-descending = abap_true THEN - result ELSE result ).
            IF result = 0.
              " the natural order, also when descending
              result = compare_siblings( member1 = previous1 member2 = previous2 ).
            ENDIF.
          ENDIF.
          RETURN.
        ENDIF.
      ENDIF.
    ENDDO.
  ENDMETHOD.

  METHOD evaluate_key.
    result = COND #( WHEN key-expression IS BOUND THEN evaluate_value( evaluator = evaluator node = key-expression )
                     ELSE evaluator->evaluate_current( ) ).
  ENDMETHOD.

  METHOD dependent_members.
    " the cell of the context depends on every hierarchy
    LOOP AT tuple INTO DATA(member).
      IF key-expression IS NOT BOUND
          OR depends_on( node = key-expression hierarchy = member-hier_id as_value = abap_true ) = abap_true.
        APPEND member TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD depends_on.
    IF node->kind = zzxxmla1_cl_mdx_node=>c_kind-literal.
      RETURN.
    ENDIF.
    DATA(type) = node->get_type( ).
    IF as_value = abap_true AND ( type->kind = zzxxmla1_cl_mdx_type=>c_kind-member
        OR type->kind = zzxxmla1_cl_mdx_type=>c_kind-tuple OR type->kind = zzxxmla1_cl_mdx_type=>c_kind-hierarchy
        OR type->kind = zzxxmla1_cl_mdx_type=>c_kind-dimension ).
      " MemberValueCalc / TupleValueCalc: the cell with the members set depends on every other hierarchy
      result = xsdbool( depends_on( node = node hierarchy = hierarchy as_value = abap_false ) = abap_true
                        OR type->uses_hierarchy( hierarchy = hierarchy
                                                 dimension_of_hierarchy = schema_reader->dimension_of( hierarchy )
                                                 definitely = abap_true ) = abap_false ).
      RETURN.
    ENDIF.
    CASE node->kind.
      WHEN zzxxmla1_cl_mdx_node=>c_kind-hierarchy.
        " its current member
        result = xsdbool( node->element-id = hierarchy ).
      WHEN zzxxmla1_cl_mdx_node=>c_kind-dimension.
        DATA(dimension) = schema_reader->get_dimension( node->element-id ).
        result = xsdbool( dimension-hierarchies[ 1 ] = hierarchy ).
      WHEN zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
        " Filter, TopCount, BottomCount: anyDependsButFirst, the set sets the members it iterates
        " Sum, Avg, Min, Max likewise
        DATA(first) = COND i( WHEN node->fun_def-name = `Filter` OR node->fun_def-name = `TopCount`
                                   OR node->fun_def-name = `BottomCount` OR node->fun_def-name = `Sum`
                                   OR node->fun_def-name = `Avg` OR node->fun_def-name = `Min`
                                   OR node->fun_def-name = `Max` OR node->fun_def-name = `Generate` THEN 2 ELSE 1 ).
        IF node->fun_def-implementation = `AsFunDef`.
          " a named set is evaluated once, independent of the context
          RETURN.
        ENDIF.
        LOOP AT node->args INTO DATA(arg) FROM first.
          DATA(category) = VALUE i( node->fun_def-parameter_categories[ sy-tabix ] OPTIONAL ).
          DATA(scalar) = xsdbool( category = c_category-logical OR category = c_category-numeric
                                  OR category = c_category-string OR category = c_category-value
                                  OR category = c_category-integer OR category = c_category-datetime ).
          IF depends_on( node = arg hierarchy = hierarchy as_value = scalar ) = abap_true.
            result = abap_true.
            RETURN.
          ENDIF.
        ENDLOOP.
    ENDCASE.
  ENDMETHOD.

  METHOD compare_siblings.
    IF member1-calculated <> member2-calculated.
      result = COND #( WHEN member1-calculated = abap_true THEN 1 ELSE -1 ).
      RETURN.
    ENDIF.
    IF member1-ordinal <> member2-ordinal.
      result = COND #( WHEN member1-ordinal < member2-ordinal THEN -1 ELSE 1 ).
      RETURN.
    ENDIF.
    " RolapMemberBase.compareTo: by key; calculated members by name
    DATA(text1) = COND string( WHEN member1-calculated = abap_true THEN member1-caption ELSE member1-key ).
    DATA(text2) = COND string( WHEN member2-calculated = abap_true THEN member2-caption ELSE member2-key ).
    result = COND #( WHEN text1 < text2 THEN -1 WHEN text1 > text2 THEN 1 ).
  ENDMETHOD.

  METHOD compare_values.
    IF value1-empty = abap_true AND value2-empty = abap_true.
      RETURN.
    ELSEIF value1-empty = abap_true.
      result = -1.
      RETURN.
    ELSEIF value2-empty = abap_true.
      result = 1.
      RETURN.
    ENDIF.
    DATA(numeric1) = xsdbool( value1-kind = zzxxmla1_cl_mdx_evaluator=>c_value-numeric
                              OR value1-kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer ).
    DATA(numeric2) = xsdbool( value2-kind = zzxxmla1_cl_mdx_evaluator=>c_value-numeric
                              OR value2-kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer ).
    IF value1-kind = zzxxmla1_cl_mdx_evaluator=>c_value-string
        AND value2-kind = zzxxmla1_cl_mdx_evaluator=>c_value-string.
      " compareToIgnoreCase
      DATA(text1) = to_lower( value1-text ).
      DATA(text2) = to_lower( value2-text ).
      result = COND #( WHEN text1 < text2 THEN -1 WHEN text1 > text2 THEN 1 ).
    ELSEIF numeric1 = abap_true AND numeric2 = abap_true.
      " compareValues( double, double ): NaN after everything but positive infinity
      IF value1-special = `NAN`.
        result = COND #( WHEN value2-special = `INF` THEN -1 WHEN value2-special = `NAN` THEN 0 ELSE 1 ).
      ELSEIF value2-special = `NAN`.
        result = COND #( WHEN value1-special = `INF` THEN 1 ELSE -1 ).
      ELSE.
        DATA(rank1) = SWITCH i( value1-special WHEN `INF` THEN 1 WHEN `-INF` THEN -1 ELSE 0 ).
        DATA(rank2) = SWITCH i( value2-special WHEN `INF` THEN 1 WHEN `-INF` THEN -1 ELSE 0 ).
        IF rank1 <> rank2.
          result = COND #( WHEN rank1 < rank2 THEN -1 ELSE 1 ).
        ELSEIF rank1 = 0.
          result = COND #( WHEN value1-number < value2-number THEN -1 WHEN value1-number > value2-number THEN 1 ).
        ENDIF.
      ENDIF.
    ELSEIF value1-kind = zzxxmla1_cl_mdx_evaluator=>c_value-order_key
        AND value2-kind = zzxxmla1_cl_mdx_evaluator=>c_value-order_key.
      result = compare_order_keys( member1 = value1-member member2 = value2-member ).
    ELSE.
      fail( |Internal error: cannot compare { zzxxmla1_cl_mdx_evaluator=>to_text( value1 ) }| ).
    ENDIF.
  ENDMETHOD.

  METHOD cast.
    " the argument as the reference compiles it: a literal in parentheses is the literal
    DATA(arg) = node->args[ 1 ].
    WHILE arg->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call AND arg->fun_def-implementation = `ParenthesesFunDef`.
      arg = arg->args[ 1 ].
    ENDWHILE.
    DATA(value) = evaluate_value( evaluator = evaluator node = arg ).
    DATA(numeric) = xsdbool( value-kind = zzxxmla1_cl_mdx_evaluator=>c_value-numeric
                             OR value-kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer ).
    CASE node->fun_def-return_category.
      WHEN c_category-string.
        IF value-empty = abap_true.
          result-empty = abap_true.
          RETURN.
        ENDIF.
        " String.valueOf; a numeric literal is a BigDecimal
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string
                          text = COND #( WHEN arg->kind = zzxxmla1_cl_mdx_node=>c_kind-literal
                                              AND arg->category = zzxxmla1_cl_mdx_node=>c_category-numeric
                                         THEN arg->value
                                         ELSE zzxxmla1_cl_mdx_evaluator=>to_text( value ) ) ).
      WHEN c_category-logical.
        " null is false (BooleanNull)
        result = logical( COND #( WHEN value-empty = abap_true THEN abap_false
                                  WHEN value-kind = zzxxmla1_cl_mdx_evaluator=>c_value-logical THEN value-boolean
                                  WHEN value-kind = zzxxmla1_cl_mdx_evaluator=>c_value-string
                                    THEN xsdbool( to_lower( value-text ) = `true` )
                                  WHEN numeric = abap_true
                                    THEN xsdbool( value-special = `INF` OR ( value-special IS INITIAL
                                                                             AND value-number > 0 ) ) ) ).
        IF value-empty = abap_false AND numeric = abap_false
            AND value-kind <> zzxxmla1_cl_mdx_evaluator=>c_value-logical
            AND value-kind <> zzxxmla1_cl_mdx_evaluator=>c_value-string.
          fail( |Internal error: cannot convert value '{ zzxxmla1_cl_mdx_evaluator=>to_text( value ) }' to targetType |
             && |'BOOLEAN'| ).
        ENDIF.
      WHEN OTHERS.
        " INTEGER (Integer.parseInt / intValue) or NUMERIC (Double.valueOf / doubleValue); null stays null
        DATA(integer) = xsdbool( node->fun_def-return_category = c_category-integer ).
        IF value-empty = abap_true.
          result-empty = abap_true.
          RETURN.
        ENDIF.
        result-kind = COND #( WHEN integer = abap_true THEN zzxxmla1_cl_mdx_evaluator=>c_value-integer
                              ELSE zzxxmla1_cl_mdx_evaluator=>c_value-numeric ).
        IF value-kind = zzxxmla1_cl_mdx_evaluator=>c_value-string.
          DATA(text) = condense( value-text ).
          DATA(valid) = COND abap_bool( WHEN integer = abap_true
                                        THEN xsdbool( matches( val = value-text regex = `[+-]?[0-9]+` ) )
                                        ELSE xsdbool( matches( val = text regex = `[+-]?([0-9]+[.]?[0-9]*|[.][0-9]+)([eE][+-]?[0-9]+)?[fFdD]?` ) ) ).
          IF valid = abap_true.
            TRY.
                result-number = CONV f( replace( val = text regex = `[fFdD]$` with = `` ) ).
              CATCH cx_sy_conversion_error.
                valid = abap_false.
            ENDTRY.
          ENDIF.
          IF integer = abap_true AND valid = abap_true AND abs( result-number ) > 2147483647.
            valid = abap_false.
          ENDIF.
          IF valid = abap_false.
            " NumberFormatException
            zzxxmla1_cx_xmla=>raise_code(
              kind = `Server` code = `00HSBD02` text = `XMLA MDX execute failed`
              description = |For input string: "{ value-text }"| ).
          ENDIF.
        ELSEIF numeric = abap_true.
          result-number = value-number.
          result-special = value-special.
          IF integer = abap_true.
            " Number.intValue: towards zero, NaN 0, infinities the extreme ints
            result-number = SWITCH #( value-special WHEN `NAN` THEN 0 WHEN `INF` THEN 2147483647 WHEN `-INF` THEN -2147483648
                                      ELSE nmax( val1 = -2147483648 val2 = nmin( val1 = 2147483647
                                                                                  val2 = trunc( value-number ) ) ) ).
            CLEAR result-special.
          ENDIF.
        ELSE.
          fail( |Internal error: cannot convert value '{ zzxxmla1_cl_mdx_evaluator=>to_text( value ) }' to targetType |
             && |'{ COND #( WHEN integer = abap_true THEN `INTEGER` ELSE `NUMERIC` ) }'| ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD current_member.
    " getSlicerMembersByHierarchy: the slicer's own members, not the placeholders
    DATA names TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    LOOP AT evaluator->get_slicer_members( ) INTO DATA(member) WHERE hier_id = hierarchy AND calculated = abap_false.
      INSERT member-unique_name INTO TABLE names.
    ENDLOOP.
    IF lines( names ) > 1.
      zzxxmla1_cx_xmla=>raise_code(
        kind = `Server` code = `00HSBD02` text = `XMLA MDX execute failed`
        description = |olap4abap Error:The MDX function CURRENTMEMBER failed because the coordinate for the '|
                   && |{ schema_reader->get_hierarchy( hierarchy )-unique_name }' hierarchy contains a set| ).
    ENDIF.
    result = evaluator->get_context( hierarchy ).
  ENDMETHOD.

  METHOD compound_slicer.
    result = members.
    DATA(first) = tuples[ 1 ].
    DATA varying TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    LOOP AT first INTO DATA(member).
      DATA(position) = sy-tabix.
      DATA(unary) = abap_true.
      LOOP AT tuples INTO DATA(tuple) FROM 2.
        IF tuple[ position ]-unique_name <> member-unique_name.
          unary = abap_false.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF unary = abap_true.
        APPEND member TO result.
      ELSE.
        APPEND position TO varying.
      ENDIF.
    ENDLOOP.
    IF varying IS INITIAL.
      RETURN.
    ENDIF.
    DATA(reduced) = VALUE ty_t_tuple( FOR t IN tuples ( VALUE #( FOR p IN varying ( t[ p ] ) ) ) ).
    DATA(calc) = NEW zzxxmla1_cl_mdx_slicer_calc( engine = me tuples = reduced ).
    " the placeholder delegates to the null member of the hierarchy (RolapHierarchy.getNullMember, named #null)
    LOOP AT varying INTO position.
      member = first[ position ].
      DATA(hierarchy) = schema_reader->get_hierarchy( member-hier_id ).
      DATA(placeholder) = VALUE ty_member( hierarchy = member-hierarchy hier_id = member-hier_id
                                           unique_name = |{ hierarchy-unique_name }.[#null]| caption = `#null`
                                           level = hierarchy-levels[ 1 ] calculated = abap_true
                                           solve_order = -99999 ).
      schema_reader->add_calculated_member( placeholder ).
      schema_reader->set_calculated_member( VALUE #( member = placeholder cube_scope = abap_true ) ).
      root_evaluator->set_compiled( member = placeholder calc = calc ).
      APPEND placeholder TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_roll_up~roll_up.
    " the AGGREGATION_TYPE property: only stored measures have one
    DATA(measure) = evaluator->get_context( zzxxmla1_cl_mdx_schema_reader=>c_measures ).
    IF measure-calculated = abap_true.
      zzxxmla1_cx_mdx_evaluation=>raise_error( `Could not find an aggregator in the current evaluation context` ).
    ENDIF.
    DATA(aggregator) = schema_reader->measures[ measure-measure_index ]-aggregator.
    DATA(rollup) = SWITCH string( aggregator WHEN `sum` OR `count` THEN `sum` WHEN `min` THEN `min`
                                             WHEN `max` THEN `max` ).
    IF rollup IS INITIAL.
      fail( |The aggregation of measures with the aggregator { aggregator } is not implemented yet| ).
    ENDIF.

    " Aggregator.sum / min / max: FunUtil.sum / min / max over the values that are not null
    result = fold_values( values = evaluate_values( evaluator = evaluator tuples = tuples value = value )
                          function = rollup ).
  ENDMETHOD.

  METHOD aggregate.
    DATA(savepoint) = evaluator->savepoint( ).
    TRY.
        DATA(tuples) = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
        " a stored measure as the value: its aggregator
        IF lines( node->args ) > 1 AND node->args[ 2 ]->kind = zzxxmla1_cl_mdx_node=>c_kind-member
            AND node->args[ 2 ]->element-member-hier_id = zzxxmla1_cl_mdx_schema_reader=>c_measures
            AND node->args[ 2 ]->element-member-calculated = abap_false.
          evaluator->set_context( node->args[ 2 ]->element-member ).
        ENDIF.
        result = zzxxmla1_if_mdx_roll_up~roll_up( evaluator = evaluator tuples = tuples
                                                  value = COND #( WHEN lines( node->args ) > 1 THEN node->args[ 2 ] ) ).
      CLEANUP.
        evaluator->restore( savepoint ).
    ENDTRY.
    evaluator->restore( savepoint ).
  ENDMETHOD.

  METHOD tuple_key.
    result = concat_lines_of( table = VALUE string_table( FOR member IN tuple ( member-unique_name ) )
                              sep = cl_abap_char_utilities=>horizontal_tab ).
  ENDMETHOD.

  METHOD literal_arg.
    IF index > lines( node->args ).
      result = default_value.
      RETURN.
    ENDIF.
    DATA(arg) = node->args[ index ].
    IF arg->kind <> zzxxmla1_cl_mdx_node=>c_kind-literal OR arg->category <> zzxxmla1_cl_mdx_node=>c_category-symbol.
      compile_error( |Expected a symbol, found '{ arg->unparse( ) }'| ).
    ENDIF.
    LOOP AT allowed INTO DATA(value).
      IF to_upper( value ) = to_upper( arg->value ).
        result = value.
        RETURN.
      ENDIF.
    ENDLOOP.
    compile_error( |Allowed values are: \{{ concat_lines_of( table = allowed sep = `, ` ) }\}| ).
  ENDMETHOD.

  METHOD compile_error.
    zzxxmla1_cx_xmla=>raise_code( kind = `Server` code = `00HSBB01` text = `XMLA SOAP Body processing error`
                                  description = message ).
  ENDMETHOD.

  METHOD union.
    DATA(all) = xsdbool( literal_arg( node = node index = 3 default_value = `DISTINCT`
                                      allowed = VALUE #( ( `ALL` ) ( `DISTINCT` ) ) ) = `ALL` ).
    " FunUtil.checkCompatible
    DATA(left_type) = node->args[ 1 ]->get_type( )->strip_set_type( ).
    DATA(right_type) = node->args[ 2 ]->get_type( )->strip_set_type( ).
    IF left_type IS NOT BOUND OR right_type IS NOT BOUND
        OR left_type->is_union_compatible( right_type ) = abap_false.
      compile_error( `Expressions must have the same hierarchy` ).
    ENDIF.
    result = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
    APPEND LINES OF evaluate_set( evaluator = evaluator node = node->args[ 2 ] ) TO result.
    IF all = abap_false.
      " FunUtil.addUnique of both
      result = distinct( result ).
    ENDIF.
  ENDMETHOD.

  METHOD except.
    DATA(tuples) = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
    IF tuples IS INITIAL.
      RETURN.
    ENDIF.
    DATA excluded TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    LOOP AT evaluate_set( evaluator = evaluator node = node->args[ 2 ] ) INTO DATA(tuple).
      INSERT tuple_key( tuple ) INTO TABLE excluded.
    ENDLOOP.
    LOOP AT tuples INTO tuple.
      IF NOT line_exists( excluded[ table_line = tuple_key( tuple ) ] ).
        APPEND tuple TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD intersect.
    DATA(all) = xsdbool( literal_arg( node = node index = 3 default_value = `` allowed = VALUE #( ( `ALL` ) ) ) = `ALL` ).
    DATA(tuples) = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
    IF tuples IS INITIAL.
      RETURN.
    ENDIF.
    DATA right TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    LOOP AT evaluate_set( evaluator = evaluator node = node->args[ 2 ] ) INTO DATA(tuple).
      INSERT tuple_key( tuple ) INTO TABLE right.
    ENDLOOP.
    DATA added TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    LOOP AT tuples INTO tuple.
      DATA(key) = tuple_key( tuple ).
      IF NOT line_exists( right[ table_line = key ] ).
        CONTINUE.
      ENDIF.
      IF all = abap_false.
        INSERT key INTO TABLE added.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
      ENDIF.
      APPEND tuple TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD head_tail.
    DATA(savepoint) = evaluator->savepoint( ).
    evaluator->set_non_empty( abap_false ).
    TRY.
        result = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
        " compileInteger: a number truncated, null is 0; no count is 1
        DATA(count) = COND i( WHEN lines( node->args ) > 1
                              THEN trunc( evaluate_number( evaluator = evaluator node = node->args[ 2 ] ) )
                              ELSE 1 ).
      CLEANUP.
        evaluator->restore( savepoint ).
    ENDTRY.
    evaluator->restore( savepoint ).
    IF count <= 0.
      CLEAR result.
    ELSEIF head = abap_true.
      DELETE result FROM count + 1.
    ELSEIF lines( result ) > count.
      DELETE result TO lines( result ) - count.
    ENDIF.
  ENDMETHOD.

  METHOD distinct.
    DATA seen TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    LOOP AT tuples INTO DATA(tuple).
      INSERT tuple_key( tuple ) INTO TABLE seen.
      IF sy-subrc = 0.
        APPEND tuple TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD count.
    result-kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer.
    IF node->fun_def-syntax = zzxxmla1_cl_mdx_node=>c_syntax-property.
      " <Set>.Count: the size of the list as it is evaluated
      result-number = lines( evaluate_set( evaluator = evaluator node = node->args[ 1 ] ) ).
      RETURN.
    ENDIF.
    " the flag as written: only INCLUDEEMPTY (the default) counts the empty cells
    DATA(include_empty) = xsdbool( lines( node->args ) < 2 OR node->args[ 2 ]->value = `INCLUDEEMPTY` ).
    DATA(savepoint) = evaluator->savepoint( ).
    evaluator->set_non_empty( abap_false ).
    TRY.
        DATA(tuples) = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
        IF include_empty = abap_true.
          result-number = lines( tuples ).
        ELSE.
          LOOP AT tuples INTO DATA(tuple).
            evaluator->set_context_members( tuple ).
            IF evaluator->current_is_empty( ) = abap_false.
              result-number = result-number + 1.
            ENDIF.
          ENDLOOP.
        ENDIF.
      CLEANUP.
        evaluator->restore( savepoint ).
    ENDTRY.
    evaluator->restore( savepoint ).
  ENDMETHOD.

  METHOD evaluate_current_list.
    DATA(savepoint) = evaluator->savepoint( ).
    evaluator->set_non_empty( abap_false ).
    TRY.
        result = evaluate_set( evaluator = evaluator node = node ).
      CLEANUP.
        evaluator->restore( savepoint ).
    ENDTRY.
    evaluator->restore( savepoint ).
  ENDMETHOD.

  METHOD evaluate_values.
    DATA(savepoint) = evaluator->savepoint( ).
    evaluator->set_non_empty( abap_false ).
    TRY.
        LOOP AT tuples INTO DATA(tuple).
          evaluator->set_context_members( tuple ).
          DATA(cell) = COND #( WHEN value IS BOUND THEN evaluate_value( evaluator = evaluator node = value )
                               ELSE evaluator->evaluate_current( ) ).
          IF cell-empty = abap_true.
            CONTINUE.
          ENDIF.
          IF cell-kind <> zzxxmla1_cl_mdx_evaluator=>c_value-numeric
              AND cell-kind <> zzxxmla1_cl_mdx_evaluator=>c_value-integer.
            DATA(error) = type_error( expected = `NUMERIC` value = cell ).
            RAISE EXCEPTION error.
          ENDIF.
          APPEND cell TO result.
        ENDLOOP.
      CLEANUP.
        evaluator->restore( savepoint ).
    ENDTRY.
    evaluator->restore( savepoint ).
  ENDMETHOD.

  METHOD set_aggregate.
    DATA(tuples) = evaluate_current_list( evaluator = evaluator node = node->args[ 1 ] ).
    result = fold_values( values   = evaluate_values( evaluator = evaluator tuples = tuples
                                                      value = COND #( WHEN lines( node->args ) > 1
                                                                      THEN node->args[ 2 ] ) )
                          function = to_lower( node->fun_def-name ) ).
  ENDMETHOD.

  METHOD fold_values.
    IF values IS INITIAL.
      " DoubleNull, Util.nullValue
      result-empty = abap_true.
      RETURN.
    ENDIF.
    CASE function.
      WHEN `min` OR `max`.
        result = values[ 1 ].
        LOOP AT values INTO DATA(value) FROM 2.
          IF ( function = `min` AND java_less( value1 = value value2 = result ) = abap_true )
              OR ( function = `max` AND java_less( value1 = result value2 = value ) = abap_true ).
            result = value.
          ENDIF.
        ENDLOOP.
      WHEN OTHERS.
        LOOP AT values INTO value.
          IF result-special = `NAN` OR value-special = `NAN`
              OR ( result-special IS NOT INITIAL AND value-special IS NOT INITIAL
                   AND result-special <> value-special ).
            result-special = `NAN`.
          ELSEIF value-special IS NOT INITIAL.
            result-special = value-special.
          ELSE.
            result-number = result-number + value-number.
          ENDIF.
        ENDLOOP.
        IF function = `avg` AND result-special IS INITIAL.
          result-number = result-number / lines( values ).
        ENDIF.
    ENDCASE.
    result-kind = zzxxmla1_cl_mdx_evaluator=>c_value-numeric.
  ENDMETHOD.

  METHOD java_less.
    IF value1-special = `NAN` OR value2-special = `NAN`.
      RETURN.
    ENDIF.
    DATA(rank1) = SWITCH i( value1-special WHEN `INF` THEN 1 WHEN `-INF` THEN -1 ELSE 0 ).
    DATA(rank2) = SWITCH i( value2-special WHEN `INF` THEN 1 WHEN `-INF` THEN -1 ELSE 0 ).
    result = xsdbool( rank1 < rank2 OR ( rank1 = 0 AND rank2 = 0 AND value1-number < value2-number ) ).
  ENDMETHOD.

  METHOD rank.
    result-kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer.
    DATA(tuple) = evaluate_tuple( evaluator = evaluator node = node->args[ 1 ] ).
    DATA(key) = tuple_key( tuple ).
    IF lines( node->args ) = 2.
      " RankedTupleList, RankedMemberList: the position of the first occurrence
      LOOP AT evaluate_set( evaluator = evaluator node = node->args[ 2 ] ) INTO DATA(element).
        IF tuple_key( element ) = key.
          result-number = sy-tabix.
          RETURN.
        ENDIF.
      ENDLOOP.
      RETURN.
    ENDIF.

    " SortedListCalc: the value of each tuple of the set (non-empty off) that has one
    TYPES:
      BEGIN OF ty_ranked,
        key   TYPE string,
        value TYPE zzxxmla1_cl_mdx_evaluator=>ty_value,
      END OF ty_ranked.
    DATA ranked TYPE HASHED TABLE OF ty_ranked WITH UNIQUE KEY key.
    DATA(savepoint) = evaluator->savepoint( ).
    evaluator->set_non_empty( abap_false ).
    TRY.
        LOOP AT evaluate_set( evaluator = evaluator node = node->args[ 2 ] ) INTO element.
          evaluator->set_context_members( element ).
          DATA(value) = evaluate_value( evaluator = evaluator node = node->args[ 3 ] ).
          IF value-empty = abap_false.
            DATA(element_key) = tuple_key( element ).
            DELETE TABLE ranked WITH TABLE KEY key = element_key.
            INSERT VALUE #( key = element_key value = value ) INTO TABLE ranked.
          ENDIF.
        ENDLOOP.
      CLEANUP.
        evaluator->restore( savepoint ).
    ENDTRY.
    evaluator->restore( savepoint ).

    " a tuple of the set has its value; another one is evaluated, and if null ranks after all
    READ TABLE ranked INTO DATA(known) WITH TABLE KEY key = key.
    IF sy-subrc = 0.
      value = known-value.
    ELSE.
      TRY.
          evaluator->set_context_members( tuple ).
          value = evaluate_value( evaluator = evaluator node = node->args[ 3 ] ).
        CLEANUP.
          evaluator->restore( savepoint ).
      ENDTRY.
      evaluator->restore( savepoint ).
      IF value-empty = abap_true.
        result-number = lines( ranked ) + 1.
        RETURN.
      ENDIF.
    ENDIF.
    " the values sorted descending (DescendingValueComparator): one after the greater ones
    result-number = 1.
    LOOP AT ranked INTO DATA(other).
      IF compare_values( value1 = other-value value2 = value ) > 0.
        result-number = result-number + 1.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD set_to_str.
    DATA texts TYPE string_table.
    LOOP AT evaluate_set( evaluator = evaluator node = node->args[ 1 ] ) INTO DATA(tuple).
      DATA(names) = concat_lines_of( table = VALUE string_table( FOR member IN tuple ( member-unique_name ) )
                                     sep = `, ` ).
      " memberSetToStr, tupleSetToStr (appendTuple)
      APPEND COND string( WHEN lines( tuple ) = 1 THEN names ELSE |({ names })| ) TO texts.
    ENDLOOP.
    result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string
                      text = |\{{ concat_lines_of( table = texts sep = `, ` ) }\}| ).
  ENDMETHOD.

  METHOD set_item.
    DATA(tuples) = evaluate_current_list( evaluator = evaluator node = node->args[ 1 ] ).
    IF node->args[ 2 ]->get_type( )->kind = zzxxmla1_cl_mdx_type=>c_kind-string.
      " the first tuple whose members have the names (Member.getName), compared as written
      DATA names TYPE string_table.
      LOOP AT node->args INTO DATA(arg) FROM 2.
        APPEND evaluate_string( evaluator = evaluator node = arg )-text TO names.
      ENDLOOP.
      LOOP AT tuples INTO DATA(tuple).
        DATA(match) = abap_true.
        LOOP AT names INTO DATA(name).
          IF tuple[ sy-tabix ]-caption <> name.
            match = abap_false.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF match = abap_true.
          result = tuple.
          RETURN.
        ENDIF.
      ENDLOOP.
    ELSE.
      " compileInteger: a number truncated
      DATA(index) = CONV i( trunc( evaluate_number( evaluator = evaluator node = node->args[ 2 ] ) ) ).
      IF index >= 0 AND index < lines( tuples ).
        result = tuples[ index + 1 ].
        RETURN.
      ENDIF.
    ENDIF.
    " makeNullMember, makeNullTuple: the null member of each hierarchy of the set's type
    DATA(element_type) = node->args[ 1 ]->get_type( )->element_type.
    DATA(element_types) = COND zzxxmla1_cl_mdx_type=>ty_t_type(
      WHEN element_type->kind = zzxxmla1_cl_mdx_type=>c_kind-tuple THEN element_type->element_types
      ELSE VALUE #( ( element_type ) ) ).
    LOOP AT element_types INTO DATA(type).
      IF type->get_hierarchy( ) = zzxxmla1_cl_mdx_type=>c_none.
        fail( `The null member of an unknown hierarchy is not implemented yet` ).
      ENDIF.
      APPEND null_member( type->get_hierarchy( ) ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD tuple_item.
    DATA(tuple) = evaluate_tuple( evaluator = evaluator node = node->args[ 1 ] ).
    DATA(index) = CONV i( trunc( evaluate_number( evaluator = evaluator node = node->args[ 2 ] ) ) ).
    IF index < 0 OR index >= lines( tuple ).
      fail( `The null member (the hierarchy's #null member) is not implemented yet` ).
    ENDIF.
    result = tuple[ index + 1 ].
  ENDMETHOD.

  METHOD named_set_tuples.
    READ TABLE named_set_values INTO DATA(known) WITH TABLE KEY key = node->set_key.
    IF sy-subrc = 0 AND anew = abap_false.
      result = known-tuples.
      RETURN.
    ENDIF.
    " RolapResult.evaluateExp: a child of the slicer evaluator, evaluating the axes if the context is
    DATA(savepoint) = evaluator->savepoint( ).
    TRY.
        evaluator->set_context_members( slicer_evaluator_context ).
        evaluator->set_non_empty( abap_false ).
        result = evaluate_set( evaluator = evaluator node = node->set_expression ).
      CLEANUP.
        evaluator->restore( savepoint ).
    ENDTRY.
    evaluator->restore( savepoint ).
    DELETE TABLE named_set_values WITH TABLE KEY key = node->set_key.
    INSERT VALUE #( key = node->set_key tuples = result ) INTO TABLE named_set_values.
  ENDMETHOD.

  METHOD set_position.
    DATA(set) = node.
    IF set->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call AND set->fun_def-implementation = `AsFunDef`.
      set = set->args[ 2 ].
    ENDIF.
    IF set->kind <> zzxxmla1_cl_mdx_node=>c_kind-named_set.
      RETURN.
    ENDIF.
    ASSIGN named_set_values[ key = set->set_key ] TO FIELD-SYMBOL(<value>).
    IF sy-subrc = 0.
      <value>-ordinal = index - 1.
    ENDIF.
  ENDMETHOD.

  METHOD named_set_current.
    DATA(tuples) = named_set_tuples( evaluator = evaluator node = node->args[ 1 ] ).
    DATA(ordinal) = named_set_values[ key = node->args[ 1 ]->set_key ]-ordinal.
    IF ordinal >= lines( tuples ).
      " list.get: IndexOutOfBoundsException
      fail( |Index: { ordinal }, Size: { lines( tuples ) }| ).
    ENDIF.
    result = tuples[ ordinal + 1 ].
  ENDMETHOD.

  METHOD generate.
    DATA(all) = xsdbool( literal_arg( node = node index = 3 default_value = `` allowed = VALUE #( ( `ALL` ) ) ) = `ALL` ).
    DATA(savepoint) = evaluator->savepoint( ).
    evaluator->set_non_empty( abap_false ).
    TRY.
        DATA(tuples) = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
      CLEANUP.
        evaluator->restore( savepoint ).
    ENDTRY.
    evaluator->restore( savepoint ).
    DATA emitted TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    TRY.
        LOOP AT tuples INTO DATA(tuple).
          set_position( node = node->args[ 1 ] index = sy-tabix ).
          evaluator->set_context_members( tuple ).
          LOOP AT evaluate_set( evaluator = evaluator node = node->args[ 2 ] ) INTO DATA(generated).
            IF all = abap_false.
              INSERT tuple_key( generated ) INTO TABLE emitted.
              IF sy-subrc <> 0.
                CONTINUE.
              ENDIF.
            ENDIF.
            APPEND generated TO result.
          ENDLOOP.
        ENDLOOP.
      CLEANUP.
        evaluator->restore( savepoint ).
    ENDTRY.
    evaluator->restore( savepoint ).
  ENDMETHOD.

  METHOD generate_string.
    DATA(text) = ``.
    DATA(savepoint) = evaluator->savepoint( ).
    TRY.
        LOOP AT evaluate_set( evaluator = evaluator node = node->args[ 1 ] ) INTO DATA(tuple).
          DATA(index) = sy-tabix.
          set_position( node = node->args[ 1 ] index = index ).
          evaluator->set_context_members( tuple ).
          " StringBuilder.append: null is the text null
          IF index > 1 AND lines( node->args ) = 3.
            text = text && zzxxmla1_cl_mdx_evaluator=>to_text( evaluate_string( evaluator = evaluator
                                                                                node = node->args[ 3 ] ) ).
          ENDIF.
          IF node->fun_def-signature_categories[ 2 ] = c_category-numeric.
            text = text && vba_str( evaluate_value( evaluator = evaluator node = node->args[ 2 ] ) ).
          ELSE.
            text = text && zzxxmla1_cl_mdx_evaluator=>to_text( evaluate_string( evaluator = evaluator
                                                                                node = node->args[ 2 ] ) ).
          ENDIF.
        ENDLOOP.
      CLEANUP.
        evaluator->restore( savepoint ).
    ENDTRY.
    evaluator->restore( savepoint ).
    result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string text = text ).
  ENDMETHOD.

  METHOD vba_str.
    result = zzxxmla1_cl_mdx_evaluator=>to_text( value ).
    IF value-empty = abap_false AND ( value-special = `INF` OR ( value-special IS INITIAL AND value-number >= 0 ) ).
      result = ` ` && result.
    ENDIF.
  ENDMETHOD.

  METHOD null_member.
    DATA(definition) = schema_reader->get_hierarchy( hierarchy ).
    DATA(level) = schema_reader->get_level( definition-levels[ 1 ] ).
    " a level like the All level (depth 0), the name #null (RolapUtil.mdxNullLiteral)
    result = VALUE #( hierarchy = definition-unique_name hier_id = hierarchy unique_name = |{ definition-unique_name }.[#null]|
                      caption = `#null` level = level-id level_name = level-unique_name is_null = abap_true ).
  ENDMETHOD.

  METHOD without_null_tuples.
    DATA(has_null) = abap_false.
    LOOP AT tuples INTO DATA(tuple).
      IF line_exists( tuple[ is_null = abap_true ] ).
        has_null = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    IF has_null = abap_false.
      RETURN.
    ENDIF.
    DATA(kept) = VALUE ty_t_tuple( ).
    LOOP AT tuples INTO tuple.
      IF NOT line_exists( tuple[ is_null = abap_true ] ).
        APPEND tuple TO kept.
      ENDIF.
    ENDLOOP.
    tuples = kept.
  ENDMETHOD.

  METHOD navigate.
    DATA(member) = evaluate_member( evaluator = evaluator node = node->args[ 1 ] ).
    CASE to_upper( node->fun_def-name ).
      WHEN `PARENT`.
        result = schema_reader->get_parent_member( member ).
      WHEN `FIRSTCHILD` OR `LASTCHILD`.
        DATA(children) = schema_reader->get_member_children( member ).
        IF children IS NOT INITIAL.
          result = children[ COND #( WHEN node->fun_def-name = `FirstChild` THEN 1 ELSE lines( children ) ) ].
        ENDIF.
      WHEN `FIRSTSIBLING` OR `LASTSIBLING`.
        IF member-is_null = abap_true.
          result = member.
          RETURN.
        ENDIF.
        DATA(siblings) = siblings_of( member ).
        IF siblings IS NOT INITIAL.
          result = siblings[ COND #( WHEN node->fun_def-name = `FirstSibling` THEN 1 ELSE lines( siblings ) ) ].
        ENDIF.
      WHEN `NEXTMEMBER`.
        result = lead_member( member = member n = 1 ).
      WHEN `PREVMEMBER`.
        result = lead_member( member = member n = -1 ).
      WHEN `LAG` OR `LEAD`.
        " compileInteger: a number truncated; Lag negates it (Integer.MIN_VALUE first made MIN_VALUE + 1)
        DATA(n) = CONV int8( trunc( evaluate_number( evaluator = evaluator node = node->args[ 2 ] ) ) ).
        IF to_upper( node->fun_def-name ) = `LAG`.
          n = - nmax( val1 = n val2 = -2147483647 ).
        ENDIF.
        result = lead_member( member = member n = n ).
    ENDCASE.
    IF result IS INITIAL.
      result = null_member( member-hier_id ).
    ENDIF.
  ENDMETHOD.

  METHOD siblings_of.
    IF member-is_null = abap_true.
      RETURN.
    ENDIF.
    DATA(parent) = schema_reader->get_parent_member( member ).
    result = COND #( WHEN parent IS INITIAL THEN schema_reader->get_hierarchy_root_members( member-hier_id )
                     ELSE schema_reader->get_member_children( parent ) ).
  ENDMETHOD.

  METHOD lead_member.
    IF n = 0 OR member-is_null = abap_true.
      result = member.
      RETURN.
    ENDIF.
    " SiblingIterator: the members of the level in hierarchy order, across parents
    DATA(members) = schema_reader->get_level_members( member-level ).
    READ TABLE members WITH KEY unique_name = member-unique_name TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      DATA(target) = sy-tabix + n.
      IF target >= 1 AND target <= lines( members ).
        result = members[ target ].
        RETURN.
      ENDIF.
    ENDIF.
    result = null_member( member-hier_id ).
  ENDMETHOD.

  METHOD ancestor.
    IF level > 0 AND schema_reader->get_level( level )-hierarchy <> member-hier_id.
      execute_error( |The member '{ member-unique_name }' is not in the same hierarchy as the level '|
                  && |{ schema_reader->get_level( level )-unique_name }'.| ).
    ENDIF.
    IF distance = 0.
      result = member.
      RETURN.
    ELSEIF distance < 0.
      result = null_member( member-hier_id ).
      RETURN.
    ENDIF.
    " the ancestors from the parent up (all visible): the one at the level, else at the distance
    DATA(remaining) = distance.
    DATA(current) = schema_reader->get_parent_member( member ).
    WHILE current IS NOT INITIAL.
      IF level > 0.
        IF current-level = level.
          result = current.
          RETURN.
        ENDIF.
      ELSE.
        remaining = remaining - 1.
        IF remaining = 0.
          result = current.
          RETURN.
        ENDIF.
      ENDIF.
      current = schema_reader->get_parent_member( current ).
    ENDWHILE.
    result = null_member( member-hier_id ).
  ENDMETHOD.

  METHOD ancestors.
    DATA(distance) = 0.
    DATA(member) = VALUE ty_member( ).
    IF node->fun_def-signature_categories[ 2 ] = c_category-level.
      DATA(level) = evaluate_level( evaluator = evaluator node = node->args[ 2 ] ).
      member = evaluate_member( evaluator = evaluator node = node->args[ 1 ] ).
      distance = depth_of( member ) - schema_reader->get_level( level )-depth.
    ELSE.
      member = evaluate_member( evaluator = evaluator node = node->args[ 1 ] ).
      distance = trunc( evaluate_number( evaluator = evaluator node = node->args[ 2 ] ) ).
    ENDIF.
    DO distance TIMES.
      APPEND VALUE #( ( ancestor( member = member distance = sy-index ) ) ) TO result.
    ENDDO.
  ENDMETHOD.

  METHOD cousin.
    IF ancestor-is_null = abap_true.
      result = ancestor.
      RETURN.
    ENDIF.
    IF member-hier_id <> ancestor-hier_id.
      execute_error( |The member arguments to the Cousin function must be from the same hierarchy. The members are '|
                  && |{ member-unique_name }' and '{ ancestor-unique_name }'.| ).
    ENDIF.
    IF depth_of( member ) < depth_of( ancestor ).
      result = null_member( member-hier_id ).
      RETURN.
    ENDIF.
    result = cousin2( member1 = member member2 = ancestor ).
    IF result IS INITIAL.
      result = null_member( member-hier_id ).
    ENDIF.
  ENDMETHOD.

  METHOD cousin2.
    IF member1 IS INITIAL.
      RETURN.
    ELSEIF member1-level = member2-level.
      result = member2.
      RETURN.
    ENDIF.
    DATA(uncle) = cousin2( member1 = schema_reader->get_parent_member( member1 ) member2 = member2 ).
    IF uncle IS INITIAL.
      RETURN.
    ENDIF.
    " Util.getMemberOrdinalInParent
    DATA(siblings) = siblings_of( member1 ).
    READ TABLE siblings WITH KEY unique_name = member1-unique_name TRANSPORTING NO FIELDS.
    DATA(ordinal) = sy-tabix.
    DATA(cousins) = schema_reader->get_member_children( uncle ).
    IF ordinal >= 1 AND ordinal <= lines( cousins ).
      result = cousins[ ordinal ].
    ENDIF.
  ENDMETHOD.

  METHOD time_hierarchy.
    result = schema_reader->get_time_hierarchy( ).
    IF result < 0.
      execute_error( |Cannot use the function '{ function_name }', no time dimension is available for this cube.| ).
    ENDIF.
  ENDMETHOD.

  METHOD parallel_period.
    DATA(count) = lines( node->args ).
    " compileInteger: a number truncated; 1 without one
    DATA(lag) = CONV int8( COND #( WHEN count >= 2
                                   THEN trunc( evaluate_number( evaluator = evaluator node = node->args[ 2 ] ) )
                                   ELSE 1 ) ).
    DATA(member) = VALUE ty_member( ).
    DATA(level) = 0.
    IF count >= 1.
      level = evaluate_level( evaluator = evaluator node = node->args[ 1 ] ).
      CASE count.
        WHEN 3.
          member = evaluate_member( evaluator = evaluator node = node->args[ 3 ] ).
        WHEN 1.
          member = current_member( evaluator = evaluator hierarchy = schema_reader->get_level( level )-hierarchy ).
        WHEN OTHERS.
          member = current_member( evaluator = evaluator hierarchy = time_hierarchy( `ParallelPeriod` ) ).
      ENDCASE.
    ELSE.
      member = current_member( evaluator = evaluator hierarchy = time_hierarchy( `ParallelPeriod` ) ).
      DATA(parent) = schema_reader->get_parent_member( member ).
      IF parent IS INITIAL.
        result = null_member( member-hier_id ).
        RETURN.
      ENDIF.
      level = parent-level.
    ENDIF.
    " parallelPeriod: the ancestor at the level, its lag-th predecessor, the cousin below it
    lag = nmax( val1 = lag val2 = -2147483647 ).
    DATA(period) = ancestor( member = member level = level
                             distance = depth_of( member ) - schema_reader->get_level( level )-depth ).
    result = cousin( member = member ancestor = lead_member( member = period n = - lag ) ).
  ENDMETHOD.

  METHOD periods_to_date.
    DATA(level) = 0.
    DATA(member) = VALUE ty_member( ).
    IF node->args IS INITIAL.
      " the time hierarchy's current member, and the level above its level
      member = current_member( evaluator = evaluator hierarchy = time_hierarchy( `PeriodsToDate` ) ).
      DATA(depth) = depth_of( member ).
      IF depth = 0.
        RETURN.
      ENDIF.
      DATA(levels) = schema_reader->get_hierarchy( member-hier_id )-levels.
      level = levels[ depth ].
    ELSE.
      level = evaluate_level( evaluator = evaluator node = node->args[ 1 ] ).
      member = COND #( WHEN lines( node->args ) > 1 THEN evaluate_member( evaluator = evaluator node = node->args[ 2 ] )
                       ELSE current_member( evaluator = evaluator
                                            hierarchy = schema_reader->get_level( level )-hierarchy ) ).
    ENDIF.
    result = periods_to_date_of( level = level member = member ).
  ENDMETHOD.

  METHOD periods_to_date_of.
    " the ancestor at the level; none if the level is below the member's
    DATA(top) = member.
    WHILE top IS NOT INITIAL AND top-level <> level.
      top = schema_reader->get_parent_member( top ).
    ENDWHILE.
    IF top IS INITIAL.
      RETURN.
    ENDIF.
    " Util.getFirstDescendantOnLevel, then the members of the level from it to the member (getMemberRange)
    DATA(first) = top.
    WHILE first-level <> member-level.
      DATA(children) = schema_reader->get_member_children( first ).
      IF children IS INITIAL.
        EXIT.
      ENDIF.
      first = children[ 1 ].
    ENDWHILE.
    LOOP AT schema_reader->get_level_members( member-level ) INTO DATA(period)
         WHERE ordinal >= first-ordinal AND ordinal <= member-ordinal.
      APPEND VALUE #( ( period ) ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD xtd.
    DATA(level_type) = SWITCH string( to_upper( node->fun_def-name ) WHEN `YTD` THEN `TimeYears`
                                                                     WHEN `QTD` THEN `TimeQuarters`
                                                                     WHEN `MTD` THEN `TimeMonths`
                                                                     ELSE `TimeWeeks` ).
    DATA(level) = schema_reader->get_time_level( level_type ).
    IF level = 0.
      execute_error( |The cube has no level of the type { level_type } for the function { node->fun_def-name }| ).
    ENDIF.
    DATA(member) = COND ty_member( WHEN node->args IS NOT INITIAL
                                   THEN evaluate_member( evaluator = evaluator node = node->args[ 1 ] )
                                   ELSE current_member( evaluator = evaluator
                                                        hierarchy = schema_reader->get_level( level )-hierarchy ) ).
    result = periods_to_date_of( level = level member = member ).
  ENDMETHOD.

  METHOD opening_closing_period.
    DATA(opening) = xsdbool( to_upper( node->fun_def-name ) = `OPENINGPERIOD` ).
    DATA(count) = lines( node->args ).
    DATA(member) = COND ty_member( WHEN count = 2 THEN evaluate_member( evaluator = evaluator node = node->args[ 2 ] )
                                   ELSE current_member( evaluator = evaluator
                                                        hierarchy = time_hierarchy( node->fun_def-name ) ) ).
    DATA(level) = 0.
    IF count >= 1.
      " a member (ClosingPeriod(<Member>), or converted to a level): compileLevel of a member is its level
      level = COND #( WHEN node->args[ 1 ]->get_type( )->kind = zzxxmla1_cl_mdx_type=>c_kind-member
                      THEN evaluate_member( evaluator = evaluator node = node->args[ 1 ] )-level
                      ELSE evaluate_level( evaluator = evaluator node = node->args[ 1 ] ) ).
    ENDIF.
    IF member-is_null = abap_true.
      result = member.
      RETURN.
    ENDIF.
    DATA(member_depth) = depth_of( member ).
    IF level = 0.
      " the level below the member's
      DATA(levels) = schema_reader->get_hierarchy( member-hier_id )-levels.
      IF lines( levels ) <= member_depth + 1.
        result = null_member( member-hier_id ).
        RETURN.
      ENDIF.
      level = levels[ member_depth + 2 ].
    ENDIF.
    DATA(target) = schema_reader->get_level( level ).
    IF target-depth < member_depth.
      result = null_member( member-hier_id ).
      RETURN.
    ENDIF.
    IF level = member-level.
      result = member.
      RETURN.
    ENDIF.
    " getDescendant: the first or last child down to the depth of the level
    DO.
      DATA(children) = schema_reader->get_member_children( member ).
      IF children IS INITIAL.
        result = null_member( target-hierarchy ).
        RETURN.
      ENDIF.
      member = COND #( WHEN opening = abap_true THEN children[ 1 ] ELSE children[ lines( children ) ] ).
      IF depth_of( member ) = target-depth.
        result = member.
        RETURN.
      ENDIF.
    ENDDO.
  ENDMETHOD.

  METHOD subset.
    DATA(savepoint) = evaluator->savepoint( ).
    evaluator->set_non_empty( abap_false ).
    TRY.
        result = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
        " compileInteger: a number truncated, null is 0
        DATA(start) = CONV i( trunc( evaluate_number( evaluator = evaluator node = node->args[ 2 ] ) ) ).
        DATA(end) = lines( result ).
        IF lines( node->args ) > 2.
          end = start + trunc( evaluate_number( evaluator = evaluator node = node->args[ 3 ] ) ).
        ENDIF.
      CLEANUP.
        evaluator->restore( savepoint ).
    ENDTRY.
    evaluator->restore( savepoint ).
    IF end > lines( result ).
      end = lines( result ).
    ENDIF.
    IF start >= end OR start < 0.
      CLEAR result.
      RETURN.
    ENDIF.
    DELETE result FROM end + 1.
    IF start > 0.
      DELETE result TO start.
    ENDIF.
  ENDMETHOD.

  METHOD evaluate_dimension.
    IF node->kind = zzxxmla1_cl_mdx_node=>c_kind-dimension.
      result = node->element-id.
      RETURN.
    ENDIF.
    IF node->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
      CASE key_of( node ).
        WHEN `DIMENSION|Property|6`.
          result = schema_reader->dimension_of( evaluate_member( evaluator = evaluator node = node->args[ 1 ] )-hier_id ).
          RETURN.
        WHEN `DIMENSION|Property|3`.
          result = schema_reader->dimension_of( evaluate_hierarchy( evaluator = evaluator node = node->args[ 1 ] ) ).
          RETURN.
        WHEN `DIMENSION|Property|4`.
          result = schema_reader->dimension_of(
                     schema_reader->get_level( evaluate_level( evaluator = evaluator node = node->args[ 1 ] ) )-hierarchy ).
          RETURN.
        WHEN `DIMENSION|Property|2`.
          result = evaluate_dimension( evaluator = evaluator node = node->args[ 1 ] ).
          RETURN.
      ENDCASE.
    ENDIF.
    result = schema_reader->dimension_of( evaluate_hierarchy( evaluator = evaluator node = node ) ).
  ENDMETHOD.

  METHOD non_empty_crossjoin.
    DATA(savepoint) = evaluator->savepoint( ).
    TRY.
        evaluator->set_non_empty( abap_true ).
        DATA(element_type) = node->get_type( )->element_type.
        LOOP AT evaluator->get_slicer_members( ) INTO DATA(slicer_member)
             WHERE hier_id <> zzxxmla1_cl_mdx_schema_reader=>c_measures.
          IF element_type IS BOUND AND element_type->uses_hierarchy(
               hierarchy = slicer_member-hier_id
               dimension_of_hierarchy = schema_reader->dimension_of( slicer_member-hier_id )
               definitely = abap_true ) = abap_true.
            DATA(all) = schema_reader->get_hierarchy_members( slicer_member-hier_id ).
            IF all IS NOT INITIAL AND all[ 1 ]-key_level = 0.
              evaluator->set_context( all[ 1 ] ).
            ENDIF.
          ENDIF.
        ENDLOOP.
        DATA native TYPE abap_bool.
        result = native_crossjoin( EXPORTING evaluator = evaluator node = node IMPORTING native = native ).
        IF native = abap_false.
          result = evaluate_arg_as_set( evaluator = evaluator call = node index = 1 ).
          IF result IS NOT INITIAL.
            result = non_empty_list( evaluator = evaluator
                                     tuples = cross_join( left = result
                                                          right = evaluate_arg_as_set( evaluator = evaluator call = node
                                                                                       index = 2 ) ) ).
          ENDIF.
        ENDIF.
      CLEANUP.
        evaluator->restore( savepoint ).
    ENDTRY.
    evaluator->restore( savepoint ).
  ENDMETHOD.

  METHOD native_crossjoin.
    CLEAR native.
    IF evaluator->is_non_empty( ) = abap_false OR lines( node->args ) <> 2.
      RETURN.
    ENDIF.
    DATA(name) = to_upper( node->fun_def-name ).
    IF name <> `CROSSJOIN` AND name <> `NONEMPTYCROSSJOIN`.
      RETURN.
    ENDIF.
    DATA operands TYPE zzxxmla1_cl_mdx_node=>ty_t_node.
    crossjoin_operands( EXPORTING node = node CHANGING operands = operands ).

    " the arguments as they are (checkCrossJoin)
    DATA args TYPE ty_t_cj_arg.
    DATA(direct) = abap_true.
    LOOP AT operands INTO DATA(operand).
      direct_cj_arg( EXPORTING node = operand IMPORTING arg = DATA(arg) found = DATA(found) ).
      IF found = abap_false.
        direct = abap_false.
        EXIT.
      ENDIF.
      APPEND arg TO args.
    ENDLOOP.
    IF direct = abap_true.
      IF valid_cj_args( evaluator = evaluator args = args ) = abap_true.
        native = abap_true.
        result = read_native_tuples( evaluator = evaluator args = args ).
      ENDIF.
      RETURN.
    ENDIF.

    " tryMultiVariantCrossJoin: at most 8 operands and 128 variants; some operand must split
    IF lines( operands ) > 8.
      RETURN.
    ENDIF.
    DATA states TYPE ty_t_cj_args.
    DATA orders TYPE ty_t_member_positions.
    DATA positions TYPE ty_member_positions.
    DATA(variant_count) = 1.
    DATA(split) = abap_false.
    LOOP AT operands INTO operand.
      DATA(operand_args) = operand_states( EXPORTING evaluator = evaluator node = operand
                                           IMPORTING positions = positions ).
      APPEND positions TO orders.
      IF operand_args IS INITIAL.
        RETURN.
      ENDIF.
      IF lines( operand_args ) > 1.
        split = abap_true.
      ENDIF.
      APPEND operand_args TO states.
      variant_count = variant_count * lines( operand_args ).
      IF variant_count > 128.
        RETURN.
      ENDIF.
    ENDLOOP.
    IF split = abap_false.
      RETURN.
    ENDIF.
    " enumerateVariants: nested loops, the first operand slowest
    DATA variants TYPE ty_t_cj_args.
    DO variant_count TIMES.
      DATA(rest) = sy-index - 1.
      DATA(variant) = VALUE ty_t_cj_arg( ).
      DATA(position) = lines( states ).
      WHILE position > 0.
        DATA(choices) = states[ position ].
        INSERT choices[ rest MOD lines( choices ) + 1 ] INTO variant INDEX 1.
        rest = rest DIV lines( choices ).
        position = position - 1.
      ENDWHILE.
      APPEND variant TO variants.
    ENDDO.
    " every variant but a trivial one (one member per argument) must be valid
    LOOP AT variants INTO variant.
      IF is_trivial_variant( variant ) = abap_true.
        CONTINUE.
      ENDIF.
      IF valid_cj_args( evaluator = evaluator args = variant ) = abap_false.
        RETURN.
      ENDIF.
    ENDLOOP.
    native = abap_true.
    LOOP AT variants INTO variant.
      IF is_trivial_variant( variant ) = abap_true.
        " a trivial variant: its tuple as it is
        APPEND VALUE #( FOR v IN variant ( v-members[ 1 ] ) ) TO result.
      ELSE.
        APPEND LINES OF read_native_tuples( evaluator = evaluator args = variant ) TO result.
      ENDIF.
    ENDLOOP.
    " the variants follow one another by level: a drilled member's children would come after the level above it
    result = in_operand_order( tuples = result orders = orders ).
  ENDMETHOD.

  METHOD in_operand_order.
    TYPES:
      BEGIN OF ty_keyed,
        key   TYPE string,
        tuple TYPE ty_tuple,
      END OF ty_keyed.
    DATA keyed TYPE STANDARD TABLE OF ty_keyed WITH EMPTY KEY.
    IF lines( tuples ) < 2.
      result = tuples.
      RETURN.
    ENDIF.
    LOOP AT tuples INTO DATA(tuple).
      " the key: per member its position in its operand, else its ordinal in the hierarchy, ten digits each
      DATA(key) = ``.
      LOOP AT tuple INTO DATA(member).
        DATA(rank) = member-ordinal.
        IF sy-tabix <= lines( orders ).
          ASSIGN orders[ sy-tabix ] TO FIELD-SYMBOL(<positions>).
          READ TABLE <positions> INTO DATA(position) WITH TABLE KEY unique_name = member-unique_name.
          IF sy-subrc = 0.
            rank = position-position.
          ENDIF.
        ENDIF.
        key = key && |{ rank WIDTH = 10 ALIGN = RIGHT PAD = '0' }|.
      ENDLOOP.
      APPEND VALUE #( key = key tuple = tuple ) TO keyed.
    ENDLOOP.
    SORT keyed STABLE BY key.
    result = VALUE #( FOR entry IN keyed ( entry-tuple ) ).
  ENDMETHOD.

  METHOD crossjoin_operands.
    IF node->kind = zzxxmla1_cl_mdx_node=>c_kind-resolved_call AND lines( node->args ) = 2
        AND ( to_upper( node->fun_def-name ) = `CROSSJOIN` OR to_upper( node->fun_def-name ) = `NONEMPTYCROSSJOIN` ).
      crossjoin_operands( EXPORTING node = node->args[ 1 ] CHANGING operands = operands ).
      crossjoin_operands( EXPORTING node = node->args[ 2 ] CHANGING operands = operands ).
    ELSE.
      APPEND node TO operands.
    ENDIF.
  ENDMETHOD.

  METHOD direct_cj_arg.
    CLEAR: arg, found.
    IF node->kind = zzxxmla1_cl_mdx_node=>c_kind-named_set.
      IF node->set_expression IS BOUND.
        direct_cj_arg( EXPORTING node = node->set_expression IMPORTING arg = arg found = found ).
      ENDIF.
      RETURN.
    ENDIF.
    IF node->kind <> zzxxmla1_cl_mdx_node=>c_kind-resolved_call.
      RETURN.
    ENDIF.
    DATA(name) = to_upper( node->fun_def-name ).
    DATA(args) = node->args.
    DATA(level) = 0.
    DATA(ancestor) = VALUE ty_member( ).
    IF name = `CHILDREN` AND lines( args ) = 1 AND args[ 1 ]->kind = zzxxmla1_cl_mdx_node=>c_kind-member.
      " checkMemberChildren: the child level below a stored member
      ancestor = args[ 1 ]->element-member.
      DATA(levels) = schema_reader->get_hierarchy( ancestor-hier_id )-levels.
      DATA(depth) = depth_of( ancestor ) + 1.
      IF ancestor-calculated = abap_true OR depth >= lines( levels ).
        RETURN.
      ENDIF.
      level = levels[ depth + 1 ].
    ELSEIF ( name = `MEMBERS` OR name = `ALLMEMBERS` ) AND lines( args ) = 1
        AND args[ 1 ]->kind = zzxxmla1_cl_mdx_node=>c_kind-level.
      " checkLevelMembers
      level = args[ 1 ]->element-id.
    ELSEIF name = `DESCENDANTS` AND lines( args ) = 2 AND args[ 1 ]->kind = zzxxmla1_cl_mdx_node=>c_kind-member.
      " checkDescendants: a level, or a depth below the member
      ancestor = args[ 1 ]->element-member.
      IF ancestor-calculated = abap_true.
        RETURN.
      ENDIF.
      IF args[ 2 ]->kind = zzxxmla1_cl_mdx_node=>c_kind-level.
        level = args[ 2 ]->element-id.
      ELSEIF args[ 2 ]->kind = zzxxmla1_cl_mdx_node=>c_kind-literal
          AND args[ 2 ]->category = zzxxmla1_cl_mdx_node=>c_category-numeric.
        levels = schema_reader->get_hierarchy( ancestor-hier_id )-levels.
        depth = depth_of( ancestor ) + CONV i( args[ 2 ]->number ).
        IF depth >= lines( levels ) OR depth < 0.
          RETURN.
        ENDIF.
        level = levels[ depth + 1 ].
      ELSE.
        RETURN.
      ENDIF.
    ELSEIF node->fun_def-implementation = `SetFunDef`.
      IF lines( args ) = 1 AND args[ 1 ]->kind <> zzxxmla1_cl_mdx_node=>c_kind-member.
        " redundant braces
        direct_cj_arg( EXPORTING node = args[ 1 ] IMPORTING arg = arg found = found ).
        RETURN.
      ENDIF.
      " checkEnumeration: stored members (MemberExpr) of one level, any number of them (see member_list_cj_arg)
      DATA(members) = VALUE ty_t_member( ).
      LOOP AT args INTO DATA(item).
        IF item->kind <> zzxxmla1_cl_mdx_node=>c_kind-member OR item->element-member-calculated = abap_true.
          RETURN.
        ENDIF.
        APPEND item->element-member TO members.
      ENDLOOP.
      member_list_cj_arg( EXPORTING members = members IMPORTING arg = arg found = found ).
      RETURN.
    ELSEIF name = `NATIVIZESET` AND lines( args ) = 1.
      direct_cj_arg( EXPORTING node = args[ 1 ] IMPORTING arg = arg found = found ).
      RETURN.
    ELSE.
      RETURN.
    ENDIF.
    " DescendantsCrossJoinArg: the level's members, below the member if there is one
    arg = VALUE #( hierarchy = schema_reader->get_level( level )-hierarchy level = level has_non_calc = abap_true ).
    LOOP AT schema_reader->get_level_members( level ) INTO DATA(member).
      IF ancestor IS INITIAL OR is_ancestor_of( ancestor = ancestor member = member ) = abap_true.
        APPEND member TO arg-members.
      ENDIF.
    ENDLOOP.
    found = abap_true.
  ENDMETHOD.

  METHOD member_list_cj_arg.
    CLEAR: arg, found.
    arg-member_list = abap_true.
    arg-level = -1.
    DATA(null_level) = -1.
    LOOP AT members INTO DATA(member).
      IF member-is_null = abap_true.
        null_level = member-level.
        CONTINUE.
      ENDIF.
      IF member-key_level = 0 AND member-calculated = abap_false.
        arg-has_all = abap_true.
      ENDIF.
      IF member-calculated = abap_true.
        arg-has_calc = abap_true.
      ELSE.
        arg-has_non_calc = abap_true.
      ENDIF.
      IF arg-level = -1.
        arg-level = member-level.
        arg-hierarchy = member-hier_id.
      ELSEIF arg-level <> member-level.
        RETURN.
      ENDIF.
      APPEND member TO arg-members.
    ENDLOOP.
    IF members IS INITIAL.
      arg-has_non_calc = abap_true.
    ENDIF.
    IF arg-level = -1 AND null_level <> -1.
      arg-level = null_level.
    ENDIF.
    found = abap_true.
  ENDMETHOD.

  METHOD operand_states.
    CLEAR positions.
    direct_cj_arg( EXPORTING node = node IMPORTING arg = DATA(arg) found = DATA(found) ).
    IF found = abap_true.
      result = VALUE #( ( arg ) ).
      RETURN.
    ENDIF.
    IF node->get_type( )->get_arity( ) <> 1.
      RETURN.
    ENDIF.
    DATA(tuples) = evaluate_set( evaluator = evaluator node = node ).
    check_result_limit( CONV #( lines( tuples ) ) ).
    " the position of each member (its first one), for the order of the result
    LOOP AT tuples INTO DATA(positioned).
      INSERT VALUE #( unique_name = positioned[ 1 ]-unique_name position = lines( positions ) ) INTO TABLE positions.
    ENDLOOP.
    " the members by level, the levels in the order of their first member (at most 6 levels)
    DATA by_level TYPE ty_t_member_lists.
    DATA levels TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    LOOP AT tuples INTO DATA(tuple).
      DATA(member) = tuple[ 1 ].
      READ TABLE levels TRANSPORTING NO FIELDS WITH KEY table_line = member-level.
      DATA(index) = sy-tabix.
      IF sy-subrc <> 0.
        APPEND member-level TO levels.
        APPEND VALUE #( ) TO by_level.
        index = lines( levels ).
      ENDIF.
      ASSIGN by_level[ index ] TO FIELD-SYMBOL(<level_members>).
      APPEND member TO <level_members>.
    ENDLOOP.
    IF by_level IS INITIAL OR lines( by_level ) > 6.
      RETURN.
    ENDIF.
    LOOP AT by_level INTO DATA(members).
      " no bound on the group's members, neither the reference's MAX_MEMBERS_PER_OPERAND_STATE (15,000) nor
      " MaxConstraints (our deviation: both keep the reference's IN list small; our read has none, it reads the level
      " grouped and keeps the group's members in ABAP, and they are in memory already. A bound would only send a large
      " level to the interpreted crossjoin, which builds the whole product and fails on the result limit)
      member_list_cj_arg( EXPORTING members = members IMPORTING arg = arg found = found ).
      IF found = abap_false.
        CLEAR result.
        RETURN.
      ENDIF.
      APPEND arg TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD is_trivial_variant.
    LOOP AT args INTO DATA(arg).
      IF arg-member_list = abap_false OR lines( arg-members ) <> 1.
        RETURN.
      ENDIF.
    ENDLOOP.
    result = abap_true.
  ENDMETHOD.

  METHOD valid_cj_args.
    DATA(non_native) = 0.
    DATA(members) = VALUE ty_t_member( ).
    LOOP AT args INTO DATA(arg).
      IF arg-member_list = abap_true.
        IF arg-has_all = abap_true OR ( arg-level = -1 AND arg-members IS INITIAL ).
          non_native = non_native + 1.
        ENDIF.
        IF arg-has_calc = abap_true.
          RETURN.
        ENDIF.
        APPEND LINES OF arg-members TO members.
      ENDIF.
    ENDLOOP.
    IF non_native = lines( args ).
      RETURN.
    ENDIF.
    " isPreferInterpreter: only member lists of calculated members (excluded above)
    IF measures_conflict( members ) = abap_true OR measures_conflict( evaluator->get_members( ) ) = abap_true.
      RETURN.
    ENDIF.
    " the context constraint is not ported for calculated members (an Aggregate in the slicer, a compound slicer)
    LOOP AT evaluator->get_members( ) INTO DATA(context) WHERE calculated = abap_true
         AND hier_id <> zzxxmla1_cl_mdx_schema_reader=>c_measures.
      IF NOT line_exists( args[ hierarchy = context-hier_id ] ).
        RETURN.
      ENDIF.
    ENDLOOP.
    result = abap_true.
  ENDMETHOD.

  METHOD measures_conflict.
    DATA nested TYPE ty_t_member.
    LOOP AT schema_reader->get_calculated_members( zzxxmla1_cl_mdx_schema_reader=>c_measures ) INTO DATA(measure).
      formula_members( EXPORTING node = schema_reader->get_calculated_member( measure-unique_name )-expression
                       CHANGING members = nested ).
    ENDLOOP.
    LOOP AT nested INTO DATA(in_measure).
      " anyMemberOverlaps: covered by an All member or an ancestor (or itself) of its hierarchy
      DATA(encountered) = abap_false.
      DATA(covered) = abap_false.
      LOOP AT members INTO DATA(member) WHERE hier_id = in_measure-hier_id.
        encountered = abap_true.
        IF member-key_level = 0 OR is_ancestor_of( ancestor = member member = in_measure ) = abap_true.
          covered = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF encountered = abap_true AND covered = abap_false.
        result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD formula_members.
    IF node IS NOT BOUND.
      RETURN.
    ENDIF.
    IF node->kind = zzxxmla1_cl_mdx_node=>c_kind-member.
      APPEND node->element-member TO members.
      RETURN.
    ENDIF.
    LOOP AT node->args INTO DATA(arg).
      formula_members( EXPORTING node = arg CHANGING members = members ).
    ENDLOOP.
  ENDMETHOD.

  METHOD read_native_tuples.
    " the context (makeContextConstraintSet): the stored non-All members of the other hierarchies (the arguments'
    " hierarchies at All) that are not their hierarchy's default member (removeCalculatedAndDefaultMembers)
    DATA filters TYPE zzxxmla1_cl_mdx_facts=>ty_t_filter.
    LOOP AT evaluator->get_members( ) INTO DATA(context) WHERE hier_id <> zzxxmla1_cl_mdx_schema_reader=>c_measures.
      IF line_exists( args[ hierarchy = context-hier_id ] ) OR context-calculated = abap_true
          OR context-unique_name = schema_reader->get_default_member( context-hier_id )-unique_name.
        CONTINUE.
      ENDIF.
      IF context-is_null = abap_true.
        RETURN.
      ENDIF.
      IF context-key_level > 0.
        APPEND VALUE #( hierarchy = context-hier_id level = context-key_level path = context-path ) TO filters.
      ENDIF.
    ENDLOOP.
    " the arguments: a level below the All level is read, the All level is its All member
    TYPES:
      BEGIN OF ty_lookup,
        path   TYPE string,
        member TYPE ty_member,
      END OF ty_lookup,
      ty_t_lookup TYPE HASHED TABLE OF ty_lookup WITH UNIQUE KEY path.
    DATA lookups TYPE STANDARD TABLE OF ty_t_lookup WITH EMPTY KEY.
    DATA(read) = VALUE int4_table( ).
    LOOP AT args INTO DATA(arg).
      DATA(key_level) = schema_reader->get_level( arg-level )-key_level.
      DATA(lookup) = VALUE ty_t_lookup( ).
      LOOP AT arg-members INTO DATA(member).
        INSERT VALUE #( path = member-path member = member ) INTO TABLE lookup.
      ENDLOOP.
      APPEND lookup TO lookups.
      IF key_level > 0.
        APPEND VALUE #( hierarchy = arg-hierarchy level = key_level any = abap_true ) TO filters.
        " the argument's position (the paths come in the order of the arguments that are read)
        APPEND lines( lookups ) TO read.
      ENDIF.
    ENDLOOP.
    IF read IS INITIAL.
      RETURN.
    ENDIF.

    " the combinations, ordered by the hierarchy order of the members, the first argument first
    TYPES:
      BEGIN OF ty_sorted,
        key   TYPE string,
        tuple TYPE ty_tuple,
      END OF ty_sorted.
    DATA sorted TYPE SORTED TABLE OF ty_sorted WITH NON-UNIQUE KEY key.
    LOOP AT fact_reader->non_empty_paths( filters ) INTO DATA(paths).
      DATA(tuple) = VALUE ty_tuple( ).
      DATA(key) = ``.
      DATA(complete) = abap_true.
      LOOP AT args INTO arg.
        DATA(index) = sy-tabix.
        READ TABLE read TRANSPORTING NO FIELDS WITH KEY table_line = index.
        IF sy-subrc = 0.
          DATA(path) = paths[ sy-tabix ].
          ASSIGN lookups[ index ][ path = path ] TO FIELD-SYMBOL(<lookup>).
          IF sy-subrc <> 0.
            complete = abap_false.
            EXIT.
          ENDIF.
          member = <lookup>-member.
        ELSE.
          " the All level: its member
          IF arg-members IS INITIAL.
            complete = abap_false.
            EXIT.
          ENDIF.
          member = arg-members[ 1 ].
        ENDIF.
        APPEND member TO tuple.
        key = key && |{ member-ordinal WIDTH = 10 ALIGN = RIGHT PAD = '0' }|.
      ENDLOOP.
      IF complete = abap_true.
        INSERT VALUE #( key = key tuple = tuple ) INTO TABLE sorted.
      ENDIF.
    ENDLOOP.
    result = VALUE #( FOR s IN sorted ( s-tuple ) ).
  ENDMETHOD.

  METHOD current_date_member.
    DATA(format_string) = evaluate_string( evaluator = evaluator node = node->args[ 2 ] ).
    " the query's start time
    DATA(text) = zzxxmla1_cl_mdx_format=>format_date( date = sy-datum time = sy-uzeit
                                                     format_string = zzxxmla1_cl_mdx_evaluator=>to_text( format_string ) ).
    DATA(match) = COND string( WHEN lines( node->args ) > 2 THEN node->args[ 3 ]->value ELSE `EXACT` ).
    result = lookup_member_match( segments = parse_identifier( text ) match = match ).
    IF result IS INITIAL.
      result = null_member( evaluate_hierarchy( evaluator = evaluator node = node->args[ 1 ] ) ).
    ENDIF.
  ENDMETHOD.

  METHOD lookup_member_match.
    DATA(element) = schema_reader->lookup_compound( segments ).
    IF element-kind = zzxxmla1_cl_mdx_schema_reader=>c_element-member.
      result = element-member.
      RETURN.
    ENDIF.
    IF match = `EXACT`.
      RETURN.
    ENDIF.
    " the hierarchy: the longest prefix that is a dimension or hierarchy
    DATA(start) = 0.
    DATA(hierarchy) = -1.
    DATA(prefix) = VALUE zzxxmla1_cl_mdx_node=>ty_t_segment( ).
    LOOP AT segments INTO DATA(segment).
      APPEND segment TO prefix.
      DATA(found) = schema_reader->lookup_compound( prefix ).
      CASE found-kind.
        WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-hierarchy.
          hierarchy = found-id.
          start = sy-tabix.
        WHEN zzxxmla1_cl_mdx_schema_reader=>c_element-dimension.
          DATA(dimension) = schema_reader->get_dimension( found-id ).
          hierarchy = dimension-hierarchies[ 1 ].
          start = sy-tabix.
        WHEN OTHERS.
          EXIT.
      ENDCASE.
    ENDLOOP.
    IF hierarchy < 0.
      RETURN.
    ENDIF.
    DATA(definition) = schema_reader->get_hierarchy( hierarchy ).
    DATA(first_level) = definition-levels[ 1 ].
    DATA current TYPE ty_member.
    LOOP AT segments INTO segment FROM start + 1.
      DATA(position) = sy-tabix.
      DATA(candidates) = COND ty_t_member(
        WHEN current IS INITIAL THEN VALUE #( FOR m IN schema_reader->get_hierarchy_members( hierarchy )
                                              WHERE ( level = first_level ) ( m ) )
        ELSE schema_reader->get_member_children( current ) ).
      DATA(exact) = VALUE ty_member( ).
      LOOP AT candidates INTO DATA(candidate).
        IF to_upper( candidate-caption ) = to_upper( segment-name ).
          exact = candidate.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF exact IS NOT INITIAL.
        current = exact.
        CONTINUE.
      ENDIF.
      " the search member (findBestMemberMatch: Hierarchy.createMember under the parent, keyed by the name): its unique
      " name decides against keys of another kind
      DATA(parent_unique) = COND string( WHEN current IS NOT INITIAL THEN current-unique_name
                                         ELSE definition-unique_name ).
      IF current IS INITIAL AND candidates IS NOT INITIAL AND candidates[ 1 ]-key_level = 0.
        " a hierarchy with an All member: the match at the second level
        parent_unique = candidates[ 1 ]-unique_name.
        candidates = schema_reader->get_member_children( candidates[ 1 ] ).
      ENDIF.
      " the closest sibling by key: the greatest before the name, the least after it
      DATA(search) = VALUE ty_member( key         = segment-name
                                      unique_name = |{ parent_unique }.| &&
                                                    zzxxmla1_cl_mdx_node=>quote_identifier( segment-name ) ).
      DATA(best) = VALUE ty_member( ).
      LOOP AT candidates INTO candidate.
        DATA(order) = compare_order_keys( member1 = candidate member2 = search ).
        IF match = `BEFORE` AND order < 0
            AND ( best IS INITIAL OR compare_order_keys( member1 = candidate member2 = best ) > 0 ).
          best = candidate.
        ELSEIF match = `AFTER` AND order > 0
            AND ( best IS INITIAL OR compare_order_keys( member1 = candidate member2 = best ) < 0 ).
          best = candidate.
        ENDIF.
      ENDLOOP.
      IF best IS INITIAL.
        RETURN.
      ENDIF.
      " the last (BEFORE) or first (AFTER) child on each remaining level
      DATA(remaining) = lines( segments ) - position.
      DO remaining TIMES.
        DATA(children) = schema_reader->get_member_children( best ).
        IF children IS INITIAL.
          RETURN.
        ENDIF.
        best = children[ COND #( WHEN match = `AFTER` THEN 1 ELSE lines( children ) ) ].
      ENDDO.
      result = best.
      RETURN.
    ENDLOOP.
    result = current.
  ENDMETHOD.

  METHOD parse_identifier.
    DATA(length) = strlen( text ).
    DATA(position) = 0.
    WHILE position < length.
      IF substring( val = text off = position len = 1 ) = `[`.
        " a quoted name up to the ] that is not ]]
        DATA(name) = ``.
        position = position + 1.
        WHILE position < length.
          DATA(character) = substring( val = text off = position len = 1 ).
          IF character = `]`.
            IF position + 1 < length AND substring( val = text off = position + 1 len = 1 ) = `]`.
              name = name && `]`.
              position = position + 2.
              CONTINUE.
            ENDIF.
            position = position + 1.
            EXIT.
          ENDIF.
          name = name && character.
          position = position + 1.
        ENDWHILE.
        APPEND VALUE #( name = name quoting = zzxxmla1_cl_mdx_node=>c_quoting-quoted ) TO result.
      ELSE.
        " an unquoted name up to the next point
        DATA(point) = find( val = text sub = `.` off = position ).
        IF point < 0.
          point = length.
        ENDIF.
        APPEND VALUE #( name = substring( val = text off = position len = point - position )
                        quoting = zzxxmla1_cl_mdx_node=>c_quoting-unquoted ) TO result.
        position = point.
      ENDIF.
      IF position < length AND substring( val = text off = position len = 1 ) = `.`.
        position = position + 1.
      ENDIF.
    ENDWHILE.
  ENDMETHOD.

  METHOD visual_totals.
    DATA(members) = VALUE ty_t_member( FOR tuple IN evaluate_set( evaluator = evaluator node = node->args[ 1 ] )
                                       ( tuple[ 1 ] ) ).
    DATA(totals) = members.
    DATA(index) = lines( members ).
    WHILE index > 0.
      DATA(member) = members[ index ].
      IF index < lines( members ).
        " the next member, not this very one, is this one or a descendant of it
        DATA(next) = totals[ index + 1 ].
        IF ( next-unique_name <> member-unique_name OR next-calc_name <> member-calc_name )
            AND is_ancestor_of( ancestor = member member = next ) = abap_true.
          totals[ index ] = create_visual_total( evaluator = evaluator node = node member = member index = index
                                                 members = totals ).
        ENDIF.
      ENDIF.
      index = index - 1.
    ENDWHILE.
    result = VALUE #( FOR total IN totals ( VALUE #( ( total ) ) ) ).
  ENDMETHOD.

  METHOD create_visual_total.
    result = member.
    IF lines( node->args ) > 1.
      DATA(pattern) = evaluate_string( evaluator = evaluator node = node->args[ 2 ] ).
      result-caption = substitute( pattern = zzxxmla1_cl_mdx_evaluator=>to_text( pattern ) name = member-caption ).
    ENDIF.
    result-calculated = abap_true.
    result-solve_order = 99.
    visual_total_count = visual_total_count + 1.
    result-calc_name = |VisualTotals#{ visual_total_count }|.
    DATA(wrapped) = member.
    DATA(calc) = visual_total_calc( member ).
    IF calc IS BOUND.
      wrapped = calc->member.
    ENDIF.
    " not calculated in the query, with Aggregate
    schema_reader->add_visual_total( VALUE #( member = result cube_scope = abap_true contains_aggregate = abap_true ) ).
    root_evaluator->set_compiled(
      member = result
      calc   = NEW zzxxmla1_cl_mdx_vtotal_calc(
                 engine = me member = wrapped
                 children = real_members( following_descendants( member = member index = index + 1
                                                                  members = members ) ) ) ).
  ENDMETHOD.

  METHOD following_descendants.
    DATA(position) = index.
    WHILE position <= lines( members ).
      DATA(descendant) = members[ position ].
      " strict descendants only
      IF descendant-unique_name = member-unique_name
          OR is_ancestor_of( ancestor = member member = descendant ) = abap_false.
        EXIT.
      ENDIF.
      APPEND descendant TO result.
      DATA(calc) = visual_total_calc( descendant ).
      IF calc IS BOUND.
        " the visual total, without the members it totals
        position = last_child_index( member = calc->member start = position members = members ).
      ELSE.
        position = position + 1.
      ENDIF.
    ENDWHILE.
  ENDMETHOD.

  METHOD last_child_index.
    result = start.
    DO.
      result = result + 1.
      IF result > lines( members ).
        EXIT.
      ENDIF.
      DATA(descendant) = members[ result ].
      IF descendant-unique_name = member-unique_name
          OR is_ancestor_of( ancestor = member member = descendant ) = abap_false.
        EXIT.
      ENDIF.
    ENDDO.
  ENDMETHOD.

  METHOD real_members.
    LOOP AT members INTO DATA(member).
      DATA(calc) = visual_total_calc( member ).
      IF calc IS BOUND.
        APPEND LINES OF real_members( calc->children ) TO result.
      ELSE.
        APPEND member TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD visual_total_calc.
    IF member-calc_name IS INITIAL.
      RETURN.
    ENDIF.
    DATA(calc) = root_evaluator->get_compiled( member ).
    IF calc IS BOUND AND calc IS INSTANCE OF zzxxmla1_cl_mdx_vtotal_calc.
      result = CAST #( calc ).
    ENDIF.
  ENDMETHOD.

  METHOD substitute.
    DATA(length) = strlen( pattern ).
    DATA(start) = 0.
    DO.
      DATA(asterisk) = find( val = pattern sub = `*` off = start ).
      IF asterisk < 0.
        result = result && substring( val = pattern off = start ).
        EXIT.
      ENDIF.
      IF asterisk + 1 < length AND substring( val = pattern off = asterisk + 1 len = 1 ) = `*`.
        " ** is an asterisk
        result = result && substring( val = pattern off = start len = asterisk + 1 - start ).
        start = asterisk + 2.
      ELSE.
        result = result && substring( val = pattern off = start len = asterisk - start ) && name.
        start = asterisk + 1.
      ENDIF.
    ENDDO.
  ENDMETHOD.

  METHOD name_of.
    DATA(calc) = visual_total_calc( member ).
    result = COND #( WHEN calc IS BOUND THEN name_of( calc->member ) ELSE member-caption ).
  ENDMETHOD.

  METHOD member_property.
    DATA(type) = COND i( WHEN member-is_null = abap_true THEN 5
                         WHEN member-calculated = abap_true THEN 4
                         WHEN member-hier_id = zzxxmla1_cl_mdx_schema_reader=>c_measures THEN 3
                         WHEN member-key_level = 0 THEN 2
                         ELSE 1 ).
    DATA(parent) = COND ty_member( WHEN member-is_null = abap_false THEN schema_reader->get_parent_member( member ) ).
    CASE to_upper( name ).
      WHEN `NAME` OR `MEMBER_NAME`.
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string text = name_of( member ) ).
      WHEN `CAPTION` OR `MEMBER_CAPTION`.
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string text = member-caption ).
      WHEN `MEMBER_UNIQUE_NAME`.
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string text = member-unique_name ).
      WHEN `LEVEL_UNIQUE_NAME`.
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string text = member-level_name ).
      WHEN `LEVEL_NUMBER`.
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer number = depth_of( member ) ).
      WHEN `HIERARCHY_UNIQUE_NAME`.
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string text = member-hierarchy ).
      WHEN `DIMENSION_UNIQUE_NAME`.
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string
                          text = schema_reader->get_dimension( schema_reader->dimension_of( member-hier_id ) )-unique_name ).
      WHEN `MEMBER_TYPE`.
        " Member.MemberType.ordinal: UNKNOWN, REGULAR, ALL, MEASURE, FORMULA, NULL
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer number = type ).
      WHEN `CHILDREN_CARDINALITY`.
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer
                          number = lines( schema_reader->get_member_children( member ) ) ).
      WHEN `PARENT_LEVEL`.
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer
                          number = COND #( WHEN parent IS NOT INITIAL THEN depth_of( parent ) ) ).
      WHEN `PARENT_UNIQUE_NAME`.
        IF parent IS INITIAL.
          result-empty = abap_true.
        ELSE.
          result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string text = parent-unique_name ).
        ENDIF.
      WHEN `PARENT_COUNT`.
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer
                          number = COND #( WHEN parent IS NOT INITIAL THEN 1 ) ).
      WHEN `KEY` OR `MEMBER_KEY`.
        " the All member's key is 0
        IF type = 2.
          result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer number = 0 ).
        ELSE.
          result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string text = member-key ).
        ENDIF.
      WHEN `CATALOG_NAME` OR `SCHEMA_NAME` OR `CUBE_NAME` OR `MEMBER_GUID` OR `MEMBER_ORDINAL` OR `DESCRIPTION`
        OR `VISIBLE` OR `CELL_FORMATTER` OR `CELL_FORMATTER_SCRIPT_LANGUAGE` OR `CELL_FORMATTER_SCRIPT`
        OR `BACK_COLOR` OR `CELL_EVALUATION_LIST` OR `CELL_ORDINAL` OR `FORE_COLOR` OR `FONT_NAME` OR `FONT_SIZE`
        OR `FONT_FLAGS` OR `FORMATTED_VALUE` OR `FORMAT_STRING` OR `NON_EMPTY_BEHAVIOR` OR `SOLVE_ORDER` OR `VALUE`
        OR `DATATYPE` OR `DEPTH` OR `DISPLAY_INFO` OR `DISPLAY_FOLDER` OR `LANGUAGE` OR `FORMAT_EXP`
        OR `ACTION_TYPE` OR `DRILLTHROUGH_COUNT`.
        " a valid property without a value here
        result-empty = abap_true.
      WHEN OTHERS.
        schema_reader->get_property_value( EXPORTING member   = member
                                                     name     = name
                                           IMPORTING property = DATA(level_property)
                                                     value    = DATA(value)
                                                     found    = DATA(found) ).
        IF found = abap_true.
          result = level_property_value( property = level_property value = value ).
        ELSEIF member-is_null = abap_false
            AND schema_reader->lookup_level_property( level = member-level name = name ) IS NOT INITIAL.
          result-empty = abap_true.
        ELSE.
          zzxxmla1_cx_mdx_evaluation=>raise_error( |Property '{ name }' is not valid for member '{ member-unique_name }'| ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD level_property_value.
    " the column's value as the property's type (RolapProperty, SqlMemberSource); an empty number is null
    CASE property-data_type.
      WHEN `String`.
        result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string text = value ).
      WHEN `Boolean`.
        result = VALUE #( kind    = zzxxmla1_cl_mdx_evaluator=>c_value-logical
                          boolean = xsdbool( to_upper( value ) = `TRUE` OR value = `1` OR value = `X` ) ).
      WHEN OTHERS.
        IF value IS INITIAL.
          result-empty = abap_true.
          RETURN.
        ENDIF.
        TRY.
            result = VALUE #( kind   = COND #( WHEN property-data_type = `Numeric`
                                               THEN zzxxmla1_cl_mdx_evaluator=>c_value-numeric
                                               ELSE zzxxmla1_cl_mdx_evaluator=>c_value-integer )
                              number = CONV f( value ) ).
          CATCH cx_sy_conversion_error.
            result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-string text = value ).
        ENDTRY.
    ENDCASE.
  ENDMETHOD.

  METHOD query_calculated_members.
    LOOP AT schema_reader->get_calculated_members( hierarchy ) INTO DATA(member).
      IF schema_reader->get_calculated_member( member-unique_name )-cube_scope = abap_false.
        APPEND member TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD calculated_child.
    DATA(level) = schema_reader->get_level( member-level ).
    DATA(levels) = schema_reader->get_hierarchy( member-hier_id )-levels.
    " the child level; none below the last level
    IF member-is_null = abap_false AND level-depth + 1 < lines( levels ).
      DATA(child_level) = levels[ level-depth + 2 ].
      LOOP AT query_calculated_members( member-hier_id ) INTO DATA(child)
           WHERE level = child_level AND parent_unique = member-unique_name AND caption = name.
        result = child.
        RETURN.
      ENDLOOP.
    ENDIF.
    result = null_member( member-hier_id ).
  ENDMETHOD.

  METHOD add_calculated_members.
    result = tuples.
    IF tuples IS INITIAL.
      RETURN.
    ENDIF.
    DATA levels TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    DATA(hierarchy) = tuples[ 1 ][ 1 ]-hier_id.
    LOOP AT tuples INTO DATA(tuple).
      DATA(member) = tuple[ 1 ].
      IF member-hier_id <> hierarchy.
        zzxxmla1_cx_mdx_evaluation=>raise_error(
          |Only members from the same hierarchy are allowed in the AddCalculatedMembers set: |
       && |{ schema_reader->get_hierarchy( hierarchy )-unique_name } vs { member-hierarchy }| ).
      ENDIF.
      IF NOT line_exists( levels[ table_line = member-level ] ).
        APPEND member-level TO levels.
      ENDIF.
    ENDLOOP.
    DATA(calculated) = query_calculated_members( hierarchy ).
    LOOP AT levels INTO DATA(level).
      LOOP AT calculated INTO DATA(calculated_member) WHERE level = level.
        " no parent, or the parent of a member of the set
        DATA(sibling) = xsdbool( calculated_member-parent_unique IS INITIAL ).
        LOOP AT tuples INTO tuple WHERE table_line IS NOT INITIAL.
          IF tuple[ 1 ]-parent_unique IS NOT INITIAL AND tuple[ 1 ]-parent_unique = calculated_member-parent_unique.
            sibling = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF sibling = abap_true.
          APPEND VALUE #( ( calculated_member ) ) TO result.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD drilldown_level.
    DATA(tuples) = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
    IF tuples IS INITIAL.
      RETURN.
    ENDIF.
    DATA(count) = lines( node->args ).
    DATA(categories) = node->fun_def-signature_categories.
    " INCLUDE_CALC_MEMBERS as the third argument of three or the fourth of four
    DATA(include_calculated) = xsdbool( ( count = 3 OR count = 4 )
                                        AND node->args[ count ]->category = zzxxmla1_cl_mdx_node=>c_category-symbol
                                        AND to_upper( node->args[ count ]->value ) = `INCLUDE_CALC_MEMBERS` ).
    " the calculated children by parent (getCalcMembersByParent)
    DATA calculated TYPE ty_t_member.
    IF include_calculated = abap_true.
      calculated = query_calculated_members( tuples[ 1 ][ 1 ]-hier_id ).
      DELETE calculated WHERE parent_unique IS INITIAL.
    ENDIF.

    IF count > 2 AND categories[ 3 ] = c_category-numeric.
      " the index form: each tuple, then the tuples with the children of its member at the index
      DATA(index) = CONV i( trunc( evaluate_number( evaluator = evaluator node = node->args[ 3 ] ) ) ).
      DATA(arity) = lines( tuples[ 1 ] ).
      IF index < 0 OR index >= arity.
        result = tuples.
        RETURN.
      ENDIF.
      IF include_calculated = abap_true.
        calculated = query_calculated_members( tuples[ 1 ][ index + 1 ]-hier_id ).
        DELETE calculated WHERE parent_unique IS INITIAL.
      ENDIF.
      LOOP AT tuples INTO DATA(tuple).
        APPEND tuple TO result.
        DATA(drilled) = tuple[ index + 1 ].
        DATA(children) = schema_reader->get_member_children( drilled ).
        LOOP AT calculated INTO DATA(calculated_child) WHERE parent_unique = drilled-unique_name.
          APPEND calculated_child TO children.
        ENDLOOP.
        LOOP AT children INTO DATA(child).
          DATA(clone) = tuple.
          clone[ index + 1 ] = child.
          APPEND clone TO result.
        ENDLOOP.
      ENDLOOP.
      RETURN.
    ENDIF.

    " the members (the first of each tuple, list.slice(0))
    DATA(members) = VALUE ty_t_member( FOR t IN tuples ( t[ 1 ] ) ).
    DATA(search_depth) = -1.
    IF count > 1 AND categories[ 2 ] = c_category-level.
      search_depth = schema_reader->get_level( evaluate_level( evaluator = evaluator node = node->args[ 2 ] ) )-depth.
    ELSE.
      LOOP AT members INTO DATA(member).
        search_depth = nmax( val1 = search_depth val2 = depth_of( member ) ).
      ENDLOOP.
    ENDIF.
    DATA parents TYPE ty_t_member.
    LOOP AT members INTO member.
      DATA(position) = sy-tabix.
      APPEND VALUE #( ( member ) ) TO result.
      IF depth_of( member ) <> search_depth.
        CONTINUE.
      ENDIF.
      " not followed by a descendant (isAncestorOf strict)
      DATA(followed) = abap_false.
      IF position < lines( members ).
        DATA(next_parent) = schema_reader->get_parent_member( members[ position + 1 ] ).
        followed = xsdbool( next_parent IS NOT INITIAL AND is_ancestor_of( ancestor = member member = next_parent ) = abap_true ).
      ENDIF.
      IF followed = abap_false.
        APPEND member TO parents.
      ENDIF.
    ENDLOOP.
    " the children after the whole set
    LOOP AT parents INTO DATA(parent).
      LOOP AT schema_reader->get_member_children( parent ) INTO child.
        APPEND VALUE #( ( child ) ) TO result.
      ENDLOOP.
      LOOP AT calculated INTO calculated_child WHERE parent_unique = parent-unique_name.
        APPEND VALUE #( ( calculated_child ) ) TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD drilldown_member.
    DATA(tuples) = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
    DATA(members) = evaluate_set( evaluator = evaluator node = node->args[ 2 ] ).
    IF tuples IS INITIAL OR members IS INITIAL.
      result = tuples.
      RETURN.
    ENDIF.
    " the members of the second set (its tuples have one member)
    DATA drilled TYPE ty_unique_names.
    LOOP AT members INTO DATA(member_tuple).
      INSERT member_tuple[ 1 ]-unique_name INTO TABLE drilled.
    ENDLOOP.
    " RECURSIVE only as the third of three arguments (getLiteralArg)
    DATA(recursive) = xsdbool( lines( node->args ) = 3 AND to_upper( node->args[ 3 ]->value ) = `RECURSIVE` ).
    LOOP AT tuples INTO DATA(tuple).
      APPEND tuple TO result.
      drilldown_member_tuple( EXPORTING tuple = tuple drilled = drilled recursive = recursive CHANGING result = result ).
    ENDLOOP.
  ENDMETHOD.

  METHOD drilldown_member_tuple.
    LOOP AT tuple INTO DATA(member).
      DATA(position) = sy-tabix.
      IF NOT line_exists( drilled[ table_line = member-unique_name ] ).
        CONTINUE.
      ENDIF.
      DATA(clone) = tuple.
      LOOP AT schema_reader->get_member_children( member ) INTO DATA(child).
        clone[ position ] = child.
        APPEND clone TO result.
        IF recursive = abap_true.
          drilldown_member_tuple( EXPORTING tuple = clone drilled = drilled recursive = recursive CHANGING result = result ).
        ENDIF.
      ENDLOOP.
      RETURN.
    ENDLOOP.
  ENDMETHOD.

  METHOD last_non_empty.
    DATA(tuples) = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
    DATA(position) = lines( tuples ).
    WHILE position > 0.
      DATA(member) = tuples[ position ][ 1 ].
      DATA(savepoint) = evaluator->savepoint( ).
      evaluator->set_context( member ).
      TRY.
          DATA(value) = evaluate_value( evaluator = evaluator node = node->args[ 2 ] ).
        CLEANUP.
          evaluator->restore( savepoint ).
      ENDTRY.
      evaluator->restore( savepoint ).
      IF value-empty = abap_false.
        result = member.
        RETURN.
      ENDIF.
      position = position - 1.
    ENDWHILE.
    " the null member of the set's hierarchy, else of the first hierarchy of its dimension
    DATA(hierarchy) = node->args[ 1 ]->get_type( )->get_hierarchy( ).
    IF hierarchy = zzxxmla1_cl_mdx_type=>c_none.
      DATA(dimension) = schema_reader->get_dimension( node->args[ 1 ]->get_type( )->get_dimension( ) ).
      hierarchy = dimension-hierarchies[ 1 ].
    ENDIF.
    result = null_member( hierarchy ).
  ENDMETHOD.

  METHOD modulo.
    DATA(first) = evaluate_value( evaluator = evaluator node = node->args[ 1 ] ).
    DATA(second) = evaluate_value( evaluator = evaluator node = node->args[ 2 ] ).
    IF first-empty = abap_true OR second-empty = abap_true.
      result-empty = abap_true.
      RETURN.
    ENDIF.
    IF first-kind <> zzxxmla1_cl_mdx_evaluator=>c_value-numeric AND first-kind <> zzxxmla1_cl_mdx_evaluator=>c_value-integer.
      zzxxmla1_cx_mdx_evaluation=>raise_error( |Invalid parameter. first parameter |
        && |{ zzxxmla1_cl_mdx_evaluator=>to_text( first ) } of Mod function must be of type number| ).
    ENDIF.
    IF second-kind <> zzxxmla1_cl_mdx_evaluator=>c_value-numeric
        AND second-kind <> zzxxmla1_cl_mdx_evaluator=>c_value-integer.
      zzxxmla1_cx_mdx_evaluation=>raise_error( |Invalid parameter. second parameter |
        && |{ zzxxmla1_cl_mdx_evaluator=>to_text( second ) } of Mod function must be of type number| ).
    ENDIF.
    IF second-number = 0.
      zzxxmla1_cx_mdx_evaluation=>raise_error( `/ by zero` ).
    ENDIF.
    " Vba.intNative: towards negative infinity
    result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-numeric
                      number = first-number - second-number * floor( first-number / second-number ) ).
  ENDMETHOD.

  METHOD java_cint.
    IF value-empty = abap_true.
      result-empty = abap_true.
      RETURN.
    ENDIF.
    DATA number TYPE f.
    CASE value-kind.
      WHEN zzxxmla1_cl_mdx_evaluator=>c_value-integer.
        number = value-number.
      WHEN zzxxmla1_cl_mdx_evaluator=>c_value-numeric.
        number = value-number.
        IF number <> trunc( number ).
          IF number * 2 = floor( number * 2 ).
            " ends in .5: to even
            number = floor( number / 2 + '0.5' ) * 2.
          ELSE.
            number = floor( number + '0.5' ).
          ENDIF.
        ENDIF.
      WHEN OTHERS.
        " Integer.parseInt, else Double.intValue
        DATA(text) = zzxxmla1_cl_mdx_evaluator=>to_text( value ).
        IF matches( val = text regex = `[-+]?[0-9]+` ).
          number = text.
        ELSEIF matches( val = text regex = `[-+]?([0-9]+[.]?[0-9]*|[.][0-9]+)([eE][-+]?[0-9]+)?` ).
          number = trunc( CONV f( text ) ).
        ELSE.
          zzxxmla1_cx_mdx_evaluation=>raise_error( |java.lang.NumberFormatException: For input string: "{ text }"| ).
        ENDIF.
    ENDCASE.
    result = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer number = trunc( number ) ).
  ENDMETHOD.

  METHOD format.
    DATA(value) = evaluate_value( evaluator = evaluator node = node->args[ 1 ] ).
    DATA(format_string) = zzxxmla1_cl_mdx_evaluator=>to_text( evaluate_string( evaluator = evaluator
                                                                               node = node->args[ 2 ] ) ).
    result-kind = zzxxmla1_cl_mdx_evaluator=>c_value-string.
    IF value-empty = abap_true.
      result-text = zzxxmla1_cl_mdx_format=>format_null( format_string ).
    ELSEIF value-kind = zzxxmla1_cl_mdx_evaluator=>c_value-numeric OR value-kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer.
      result-text = zzxxmla1_cl_mdx_format=>format_number( value = value-number format_string = format_string ).
    ELSE.
      result-text = zzxxmla1_cl_mdx_format=>format_text( value = zzxxmla1_cl_mdx_evaluator=>to_text( value )
                                                        format_string = format_string ).
    ENDIF.
  ENDMETHOD.

  METHOD case.
    DATA(count) = lines( node->args ).
    IF node->fun_def-implementation = `CaseTestFunDef`.
      DATA(position) = 1.
      WHILE position < count.
        IF evaluate_boolean( evaluator = evaluator node = node->args[ position ] ) = abap_true.
          result = evaluate_value( evaluator = evaluator node = node->args[ position + 1 ] ).
          RETURN.
        ENDIF.
        position = position + 2.
      ENDWHILE.
      IF count MOD 2 = 1.
        result = evaluate_value( evaluator = evaluator node = node->args[ count ] ).
      ELSE.
        result-empty = abap_true.
      ENDIF.
      RETURN.
    ENDIF.
    " CaseMatch: Object.equals of the match and the value
    DATA(value) = evaluate_value( evaluator = evaluator node = node->args[ 1 ] ).
    position = 2.
    WHILE position < count.
      DATA(match) = evaluate_value( evaluator = evaluator node = node->args[ position ] ).
      IF match-empty = abap_true.
        zzxxmla1_cx_mdx_evaluation=>raise_error( `java.lang.NullPointerException` ).
      ENDIF.
      IF value-empty = abap_false AND match-kind = value-kind AND match-number = value-number
          AND match-text = value-text AND match-boolean = value-boolean.
        result = evaluate_value( evaluator = evaluator node = node->args[ position + 1 ] ).
        RETURN.
      ENDIF.
      position = position + 2.
    ENDWHILE.
    IF count MOD 2 = 0.
      result = evaluate_value( evaluator = evaluator node = node->args[ count ] ).
    ELSE.
      result-empty = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD member_in_set.
    DATA(member) = evaluate_member( evaluator = evaluator node = node->args[ 1 ] ).
    LOOP AT evaluate_set( evaluator = evaluator node = node->args[ 2 ] ) INTO DATA(tuple).
      IF tuple[ 1 ]-unique_name = member-unique_name.
        result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD string_matches.
    DATA(text) = evaluate_string( evaluator = evaluator node = node->args[ 1 ] ).
    DATA(regex) = evaluate_string( evaluator = evaluator node = node->args[ 2 ] ).
    IF text-empty = abap_true OR regex-empty = abap_true.
      " Pattern.matches of null
      zzxxmla1_cx_mdx_evaluation=>raise_error( `java.lang.NullPointerException` ).
    ENDIF.
    result = java_matches( text = text-text regex = regex-text ).
  ENDMETHOD.

  METHOD java_matches.
    DATA(rest) = regex.
    DATA(ignore_case) = abap_false.
    WHILE strlen( rest ) >= 4 AND substring( val = rest len = 4 ) = `(?i)`.
      ignore_case = abap_true.
      rest = substring( val = rest off = 4 ).
    ENDWHILE.
    " an escaped character as it is; \Q...\E (or \Q to the end) its characters escaped
    DATA(posix) = ``.
    DATA(length) = strlen( rest ).
    DATA(position) = 0.
    WHILE position < length.
      DATA(character) = substring( val = rest off = position len = 1 ).
      IF character = `\` AND position + 1 < length.
        DATA(escaped) = substring( val = rest off = position + 1 len = 1 ).
        IF escaped = `Q`.
          DATA(end) = find( val = rest sub = `\E` off = position + 2 ).
          IF end < 0.
            end = length.
          ENDIF.
          posix = posix && escape( val = substring( val = rest off = position + 2 len = end - position - 2 )
                                   format = cl_abap_format=>e_regex ).
          position = end + 2.
        ELSE.
          posix = posix && character && escaped.
          position = position + 2.
        ENDIF.
      ELSE.
        posix = posix && character.
        position = position + 1.
      ENDIF.
    ENDWHILE.
    TRY.
        " the parameter case takes a constant only
        IF ignore_case = abap_true.
          result = xsdbool( matches( val = text regex = posix case = abap_false ) ).
        ELSE.
          result = xsdbool( matches( val = text regex = posix ) ).
        ENDIF.
      CATCH cx_sy_regex cx_sy_matcher INTO DATA(error).
        " PatternSyntaxException
        DATA(message) = error->get_text( ).
        zzxxmla1_cx_mdx_evaluation=>raise_error( message ).
    ENDTRY.
  ENDMETHOD.

  METHOD is_same.
    " the arguments' categories (a MultiResolver): objects of different kinds are not the same
    DATA(categories) = node->fun_def-parameter_categories.
    IF categories[ 1 ] <> categories[ 2 ].
      RETURN.
    ENDIF.
    CASE categories[ 1 ].
      WHEN c_category-tuple.
        " equalTuple
        DATA(tuple1) = evaluate_tuple( evaluator = evaluator node = node->args[ 1 ] ).
        DATA(tuple2) = evaluate_tuple( evaluator = evaluator node = node->args[ 2 ] ).
        IF lines( tuple1 ) <> lines( tuple2 ).
          RETURN.
        ENDIF.
        LOOP AT tuple1 INTO DATA(member).
          IF member-unique_name <> tuple2[ sy-tabix ]-unique_name.
            RETURN.
          ENDIF.
        ENDLOOP.
        result = abap_true.
      WHEN c_category-member.
        result = xsdbool( evaluate_member( evaluator = evaluator node = node->args[ 1 ] )-unique_name
                        = evaluate_member( evaluator = evaluator node = node->args[ 2 ] )-unique_name ).
      WHEN c_category-level.
        result = xsdbool( evaluate_level( evaluator = evaluator node = node->args[ 1 ] )
                        = evaluate_level( evaluator = evaluator node = node->args[ 2 ] ) ).
      WHEN c_category-hierarchy.
        result = xsdbool( evaluate_hierarchy( evaluator = evaluator node = node->args[ 1 ] )
                        = evaluate_hierarchy( evaluator = evaluator node = node->args[ 2 ] ) ).
      WHEN c_category-dimension.
        result = xsdbool( evaluate_dimension( evaluator = evaluator node = node->args[ 1 ] )
                        = evaluate_dimension( evaluator = evaluator node = node->args[ 2 ] ) ).
    ENDCASE.
  ENDMETHOD.

  METHOD existing.
    DATA(context) = evaluator->get_members( ).
    LOOP AT evaluate_set( evaluator = evaluator node = node->args[ 1 ] ) INTO DATA(tuple).
      IF exists_in_tuple( left = tuple right = context evaluator = evaluator ) = abap_true.
        APPEND tuple TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD exists.
    DATA(left_tuples) = evaluate_set( evaluator = evaluator node = node->args[ 1 ] ).
    IF left_tuples IS INITIAL.
      RETURN.
    ENDIF.
    DATA(right_tuples) = evaluate_set( evaluator = evaluator node = node->args[ 2 ] ).
    LOOP AT left_tuples INTO DATA(left).
      LOOP AT right_tuples INTO DATA(right).
        IF exists_in_tuple( left = left right = right ) = abap_true.
          APPEND left TO result.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD exists_in_tuple.
    DATA checked TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.
    LOOP AT left INTO DATA(left_member).
      DATA(right_member) = corresponding_member( member = left_member tuple = right evaluator = evaluator ).
      INSERT right_member-unique_name INTO TABLE checked.
      IF is_on_same_hierarchy_chain( member = left_member other = right_member ) = abap_false.
        RETURN.
      ENDIF.
    ENDLOOP.
    " the members of the right tuple not checked yet: they matter only where the default member is not the All member
    LOOP AT right INTO right_member.
      IF line_exists( checked[ table_line = right_member-unique_name ] ).
        CONTINUE.
      ENDIF.
      left_member = corresponding_member( member = right_member tuple = left evaluator = evaluator ).
      IF is_on_same_hierarchy_chain( member = left_member other = right_member ) = abap_false.
        RETURN.
      ENDIF.
    ENDLOOP.
    result = abap_true.
  ENDMETHOD.

  METHOD corresponding_member.
    READ TABLE tuple INTO result WITH KEY hier_id = member-hier_id.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.
    IF evaluator IS BOUND.
      result = evaluator->get_context( member-hier_id ).
    ELSE.
      result = schema_reader->get_default_member( member-hier_id ).
    ENDIF.
  ENDMETHOD.

  METHOD is_on_same_hierarchy_chain.
    IF compound_slicer_tuples( member ) IS NOT INITIAL.
      result = is_on_same_chain_internal( member = member other = other ).
    ELSE.
      result = is_on_same_chain_internal( member = other other = member ).
    ENDIF.
  ENDMETHOD.

  METHOD is_on_same_chain_internal.
    DATA(tuples) = compound_slicer_tuples( member ).
    IF tuples IS INITIAL.
      result = xsdbool( is_ancestor_of( ancestor = other member = member ) = abap_true
                     OR is_ancestor_of( ancestor = member member = other ) = abap_true ).
      RETURN.
    ENDIF.
    IF tuples[ 1 ][ 1 ]-hier_id <> other-hier_id.
      RETURN.
    ENDIF.
    LOOP AT tuples INTO DATA(tuple).
      IF is_on_same_chain_internal( member = other other = tuple[ 1 ] ) = abap_true.
        result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD is_ancestor_of.
    DATA(current) = member.
    WHILE current IS NOT INITIAL.
      IF current-unique_name = ancestor-unique_name.
        result = abap_true.
        RETURN.
      ENDIF.
      current = schema_reader->get_parent_member( current ).
    ENDWHILE.
  ENDMETHOD.

  METHOD compound_slicer_tuples.
    IF member-calculated = abap_false.
      RETURN.
    ENDIF.
    DATA(calc) = root_evaluator->get_compiled( member ).
    IF calc IS BOUND AND calc IS INSTANCE OF zzxxmla1_cl_mdx_slicer_calc.
      result = CAST zzxxmla1_cl_mdx_slicer_calc( calc )->tuples.
    ENDIF.
  ENDMETHOD.

  METHOD compare_order_keys.
    IF member1-calculated <> member2-calculated.
      result = COND #( WHEN member1-calculated = abap_true THEN 1 ELSE -1 ).
      RETURN.
    ENDIF.
    DATA(numeric1) = xsdbool( matches( val = member1-key regex = `-?[0-9]+` ) ).
    DATA(numeric2) = xsdbool( matches( val = member2-key regex = `-?[0-9]+` ) ).
    IF numeric1 <> numeric2.
      " keys of different classes: by unique name (String.compareTo)
      result = COND #( WHEN member1-unique_name < member2-unique_name THEN -1
                       WHEN member1-unique_name > member2-unique_name THEN 1 ).
    ELSEIF numeric1 = abap_true.
      DATA(number1) = CONV decfloat34( member1-key ).
      DATA(number2) = CONV decfloat34( member2-key ).
      result = COND #( WHEN number1 < number2 THEN -1 WHEN number1 > number2 THEN 1 ).
    ELSE.
      " Util.caseSensitiveCompareName: ignoring case, then with case
      DATA(lower1) = to_lower( member1-key ).
      DATA(lower2) = to_lower( member2-key ).
      result = COND #( WHEN lower1 < lower2 THEN -1 WHEN lower1 > lower2 THEN 1
                       WHEN member1-key < member2-key THEN -1 WHEN member1-key > member2-key THEN 1 ).
    ENDIF.
  ENDMETHOD.

  METHOD execute_error.
    zzxxmla1_cx_xmla=>raise_code( kind = `Server` code = `00HSBD02` text = `XMLA MDX execute failed`
                                  description = |olap4abap Error:{ message }| ).
  ENDMETHOD.

  METHOD type_error.
    DATA(actual) = SWITCH string( value-kind WHEN zzxxmla1_cl_mdx_evaluator=>c_value-string THEN `STRING`
                                             WHEN zzxxmla1_cl_mdx_evaluator=>c_value-logical THEN `BOOLEAN`
                                             ELSE `NUMERIC` ).
    result = zzxxmla1_cx_mdx_evaluation=>create(
      |Expected value of type { expected }; got value '{ zzxxmla1_cl_mdx_evaluator=>to_text( value ) }' ({ actual })| ).
  ENDMETHOD.

  METHOD compute_cell.
    " an evaluation error is the value of this cell only (RolapResult.executeStripe)
    DATA(savepoint) = evaluator->savepoint( ).
    TRY.
        DATA(value) = evaluator->evaluate_current( ).
      CATCH zzxxmla1_cx_mdx_evaluation INTO DATA(error).
        evaluator->restore( savepoint ).
        value = VALUE #( kind = zzxxmla1_cl_mdx_evaluator=>c_value-error text = error->to_text( ) ).
    ENDTRY.
    IF want_format_string = abap_true.
      " the cell property FORMAT_STRING, also of an empty cell (RolapCell.getPropertyValue)
      TRY.
          result-format_string = evaluator->get_format_string( ).
        CATCH zzxxmla1_cx_mdx_evaluation.
          evaluator->restore( savepoint ).
      ENDTRY.
    ENDIF.
    IF value-empty = abap_true.
      result-empty = abap_true.
      RETURN.
    ENDIF.
    CASE value-kind.
      WHEN zzxxmla1_cl_mdx_evaluator=>c_value-error.
        " the exception as text (Evaluator.format: #ERR: and the exception)
        result-value_type = `xsd:string`.
        result-value = value-text.
        result-formatted = |#ERR: { value-text }|.
        RETURN.
      WHEN zzxxmla1_cl_mdx_evaluator=>c_value-string OR zzxxmla1_cl_mdx_evaluator=>c_value-order_key.
        result-value_type = `xsd:string`.
        result-value = value-text.
      WHEN zzxxmla1_cl_mdx_evaluator=>c_value-integer.
        " The reference server writes an Integer as xsd:integer
        result-value_type = `xsd:integer`.
        result-value = zzxxmla1_cl_mdx_evaluator=>to_text( value ).
      WHEN zzxxmla1_cl_mdx_evaluator=>c_value-logical.
        result-value_type = `xsd:boolean`.
        result-value = zzxxmla1_cl_mdx_evaluator=>to_text( value ).
      WHEN OTHERS.
        " a double: INF for positive infinity, else Double.toString without trailing zeros
        result-value_type = `xsd:double`.
        result-value = COND #( WHEN value-special = `INF` THEN `INF`
                               WHEN value-special IS NOT INITIAL THEN zzxxmla1_cl_mdx_evaluator=>to_text( value )
                               ELSE zzxxmla1_cl_mdx_format=>xmla_double( value-number ) ).
    ENDCASE.
    " Format.format of the value with the cell's format string
    " an evaluation error of the format expression is ignored: no format string
    TRY.
        DATA(format_string) = evaluator->get_format_string( ).
      CATCH zzxxmla1_cx_mdx_evaluation.
        evaluator->restore( savepoint ).
        CLEAR format_string.
    ENDTRY.
    IF ( value-kind = zzxxmla1_cl_mdx_evaluator=>c_value-numeric AND value-special IS INITIAL )
        OR value-kind = zzxxmla1_cl_mdx_evaluator=>c_value-integer.
      result-formatted = zzxxmla1_cl_mdx_format=>format_number( value = value-number format_string = format_string ).
    ELSEIF value-kind = zzxxmla1_cl_mdx_evaluator=>c_value-string.
      result-formatted = zzxxmla1_cl_mdx_format=>format_text( value = value-text format_string = format_string ).
    ELSE.
      result-formatted = zzxxmla1_cl_mdx_evaluator=>to_text( value ).
    ENDIF.
  ENDMETHOD.

  METHOD set_display_info.
    " The reference: the number of children (at most 0xffff), 0x10000 if the next tuple's member is a child of this one,
    " 0x20000 if the parent is the one of the previous tuple's member
    TYPES:
      BEGIN OF ty_child_count,
        unique_name TYPE string,
        count       TYPE i,
      END OF ty_child_count.
    " the children of an All member are counted once, not for every tuple it is in
    DATA child_counts TYPE HASHED TABLE OF ty_child_count WITH UNIQUE KEY unique_name.
    DATA(count) = lines( tuples ).
    DO count TIMES.
      DATA(position) = sy-index.
      LOOP AT tuples[ position ] ASSIGNING FIELD-SYMBOL(<member>).
        DATA(k) = sy-tabix.
        DATA(children) = <member>-children.
        " an All member (or a visual total of one) is made without its children counted (getMemberChildren.size)
        IF <member>-key_level = 0 AND <member>-is_null = abap_false
            AND <member>-hier_id <> zzxxmla1_cl_mdx_schema_reader=>c_measures
            AND ( <member>-calculated = abap_false OR <member>-calc_name IS NOT INITIAL ).
          ASSIGN child_counts[ unique_name = <member>-unique_name ] TO FIELD-SYMBOL(<child_count>).
          IF sy-subrc <> 0.
            DATA(all_member) = <member>.
            all_member-calculated = abap_false.
            INSERT VALUE #( unique_name = <member>-unique_name
                            count = lines( schema_reader->get_member_children( all_member ) ) )
              INTO TABLE child_counts ASSIGNING <child_count>.
          ENDIF.
          children = <child_count>-count.
        ENDIF.
        <member>-display_info = nmin( val1 = children val2 = 65535 ).
        IF position < count AND tuples[ position + 1 ][ k ]-parent_unique IS NOT INITIAL
            AND tuples[ position + 1 ][ k ]-parent_unique = <member>-unique_name.
          <member>-display_info = <member>-display_info + 65536.
        ENDIF.
        IF position > 1 AND <member>-parent_unique IS NOT INITIAL
            AND <member>-parent_unique = tuples[ position - 1 ][ k ]-parent_unique.
          <member>-display_info = <member>-display_info + 131072.
        ENDIF.
      ENDLOOP.
    ENDDO.
  ENDMETHOD.

  METHOD fail.
    zzxxmla1_cx_xmla=>raise_code(
      kind = `Server` code = `00HSBB01` text = `XMLA SOAP Body processing error`
      description = |olap4abap Error:{ message }| ).
  ENDMETHOD.

ENDCLASS.
