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
"! The marks of queries on ZFMSALES: one statement per row of the principle table and per item of "What needs the
"! evaluator" of docs/query-planning.md. Each query gets a schema reader of its own, which holds its calculated members.
CLASS ltc_planner DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    CONSTANTS:
      c_static     TYPE string VALUE zzxxmla1_cl_mdx_planner=>c_mark-static,
      c_relational TYPE string VALUE zzxxmla1_cl_mdx_planner=>c_mark-relational,
      c_computed   TYPE string VALUE zzxxmla1_cl_mdx_planner=>c_mark-computed.
    DATA query TYPE zzxxmla1_cl_mdx_parser=>ty_query.
    DATA planner TYPE REF TO zzxxmla1_cl_mdx_planner.
    DATA plan TYPE zzxxmla1_cl_mdx_planner=>ty_plan.
    "! Parses, resolves and plans the query.
    METHODS plan_query
      IMPORTING mdx TYPE string
      RAISING   zzxxmla1_cx_xmla.
    "! The marks of the axes, the slicer and the cells.
    METHODS assert_plan
      IMPORTING axes   TYPE string_table
                slicer TYPE string DEFAULT ``
                cells  TYPE string
                query  TYPE string.
    "! The mark of the first axis' expression.
    METHODS assert_axis_node
      IMPORTING expected TYPE string.
    METHODS filter_list FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS stored_measures FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS no_cell_shown FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS slicer FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS compound_slicer FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS non_empty FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS member_functions FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS calculated_measure FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS unused_formula FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS calculated_slicer FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS all_members FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS include_calc_members FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS navigation_in_formula FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS sets_by_value FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS native_top_count FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS native_order FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS format_expression FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS named_sets FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS visual_totals FOR TESTING RAISING zzxxmla1_cx_xmla.
ENDCLASS.

CLASS ltc_planner IMPLEMENTATION.

  METHOD plan_query.
    DATA(reader) = zzxxmla1_cl_mdx_schema_reader=>for_cube( catalog = `` name = `ZFMSALES` ).
    query = zzxxmla1_cl_mdx_parser=>parse( mdx )-query.
    NEW zzxxmla1_cl_mdx_validator( reader )->resolve_query( CHANGING query = query ).
    planner = NEW #( reader ).
    plan = planner->plan( query ).
  ENDMETHOD.

  METHOD assert_plan.
    cl_abap_unit_assert=>assert_equals( act = VALUE string_table( FOR axis IN plan-axes ( axis-mark ) ) exp = axes
                                        msg = `axes` ).
    cl_abap_unit_assert=>assert_equals( act = plan-slicer exp = slicer msg = `slicer` ).
    cl_abap_unit_assert=>assert_equals( act = plan-cells exp = cells msg = `cells` ).
    cl_abap_unit_assert=>assert_equals( act = plan-query exp = query msg = `query` ).
  ENDMETHOD.

  METHOD assert_axis_node.
    cl_abap_unit_assert=>assert_equals( act = planner->get_mark( query-axes[ 1 ]-expression ) exp = expected ).
  ENDMETHOD.

  METHOD filter_list.
    " Excel's filter list: the axis is member reads, its non-empty filter and the cells one grouped statement
    plan_query( `SELECT NON EMPTY Hierarchize({DrilldownLevel({[Store].[All Stores]},,,INCLUDE_CALC_MEMBERS)}) `
             && `DIMENSION PROPERTIES PARENT_UNIQUE_NAME ON COLUMNS FROM [ZFMSALES] `
             && `CELL PROPERTIES VALUE, FORMAT_STRING, LANGUAGE, BACK_COLOR, FORE_COLOR, FONT_FLAGS` ).
    assert_axis_node( c_static ).
    assert_plan( axes = VALUE #( ( c_relational ) ) cells = c_relational query = c_relational ).
  ENDMETHOD.

  METHOD stored_measures.
    plan_query( `select {[Measures].[Unit Sales], [Measures].[Store Cost]} on 0, `
             && `[Store].[Store Country].Members on 1 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_static ) ( c_static ) ) cells = c_relational query = c_relational ).
  ENDMETHOD.

  METHOD no_cell_shown.
    " Excel's member lists ask for CELL_ORDINAL only
    plan_query( `select {[Store].[USA]} on 0 from [ZFMSALES] cell properties CELL_ORDINAL` ).
    assert_plan( axes = VALUE #( ( c_static ) ) cells = c_static query = c_static ).
  ENDMETHOD.

  METHOD slicer.
    " Time has no All member: its default member, as a slicer member, is a condition
    plan_query( `select {[Measures].[Unit Sales]} on 0 from [ZFMSALES] where ([Time].[1997], [Product].[All Products])` ).
    assert_plan( axes = VALUE #( ( c_static ) ) slicer = c_static cells = c_relational query = c_relational ).
  ENDMETHOD.

  METHOD compound_slicer.
    plan_query( `select {[Measures].[Unit Sales]} on 0 from [ZFMSALES] where {[Time].[1997].[Q1], [Time].[1997].[Q2]}` ).
    assert_plan( axes = VALUE #( ( c_static ) ) slicer = c_static cells = c_relational query = c_relational ).
  ENDMETHOD.

  METHOD non_empty.
    plan_query( `select NonEmpty([Store].[Store State].Members) on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_relational ) ) cells = c_relational query = c_relational ).
    plan_query( `select NonEmptyCrossJoin([Store].[Store Country].Members, [Product].Children) on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_relational ) ) cells = c_relational query = c_relational ).
    " with a second set: evaluated (step 5)
    plan_query( `select NonEmpty([Store].[Store State].Members, {[Measures].[Store Cost]}) on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_computed ) ) cells = c_relational query = c_computed ).
  ENDMETHOD.

  METHOD member_functions.
    " functions of members that read no facts are member reads
    plan_query( `select {[Store].[USA].Parent, [Store].[USA].FirstChild, [Store].[USA].Lag(1)} on 0, `
             && `Descendants([Time].[1997], [Time].[Month]) on 1, `
             && `{[Product].[Drink] : [Product].[Food]} on 2 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_static ) ( c_static ) ( c_static ) ) cells = c_relational query = c_relational ).
    plan_query( `select Head(Hierarchize(Union([Store].Children, [Store].[USA].Children)), 3) on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_static ) ) cells = c_relational query = c_relational ).
  ENDMETHOD.

  METHOD calculated_measure.
    plan_query( `with member [Measures].[Profit] as [Measures].[Store Sales] - [Measures].[Store Cost] `
             && `select {[Measures].[Profit]} on 0, [Store].Children on 1 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_computed ) ( c_static ) ) cells = c_computed query = c_computed ).
    " the formula is computed, its inputs are groups
    DATA(formula) = query-formulas[ 1 ]-expression.
    cl_abap_unit_assert=>assert_equals( act = planner->get_mark( formula ) exp = c_computed ).
    cl_abap_unit_assert=>assert_equals( act = planner->get_mark( formula->args[ 1 ] ) exp = c_static ).
  ENDMETHOD.

  METHOD unused_formula.
    plan_query( `with member [Measures].[Profit] as [Measures].[Store Sales] - [Measures].[Store Cost] `
             && `select {[Measures].[Unit Sales]} on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_static ) ) cells = c_relational query = c_relational ).
  ENDMETHOD.

  METHOD calculated_slicer.
    " a calculated member in the context makes the cells and the non-empty filter computed
    plan_query( `with member [Store].[NA] as Aggregate({[Store].[USA], [Store].[Canada]}) `
             && `select NON EMPTY [Product].Children on 0 from [ZFMSALES] where [Store].[NA]` ).
    assert_plan( axes = VALUE #( ( c_computed ) ) slicer = c_computed cells = c_computed query = c_computed ).
    " NonEmpty in that context is evaluated
    plan_query( `with member [Store].[NA] as Aggregate({[Store].[USA], [Store].[Canada]}) `
             && `select NonEmpty([Product].Children) on 0 from [ZFMSALES] where [Store].[NA]` ).
    assert_axis_node( c_computed ).
  ENDMETHOD.

  METHOD all_members.
    plan_query( `select [Measures].AllMembers on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_static ) ) cells = c_relational query = c_relational ).
    " with a calculated measure among the members
    plan_query( `with member [Measures].[Two] as 2 select [Measures].AllMembers on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_static ) ) cells = c_computed query = c_computed ).
    plan_query( `with member [Measures].[Two] as 2 select AddCalculatedMembers([Measures].Members) on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_static ) ) cells = c_computed query = c_computed ).
  ENDMETHOD.

  METHOD include_calc_members.
    " a calculated member of another hierarchy is not among the children
    plan_query( `with member [Measures].[Two] as 2 `
             && `select DrilldownLevel({[Store].[All Stores]},,,INCLUDE_CALC_MEMBERS) on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_static ) ) cells = c_relational query = c_relational ).
    plan_query( `with member [Store].[USA].[West] as Aggregate({[Store].[USA].[CA], [Store].[USA].[OR]}) `
             && `select DrilldownLevel({[Store].[USA]},,,INCLUDE_CALC_MEMBERS) on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_static ) ) cells = c_computed query = c_computed ).
  ENDMETHOD.

  METHOD navigation_in_formula.
    " which cell the formula reads depends on the cell being computed
    plan_query( `with member [Measures].[Prev] as ([Measures].[Unit Sales], [Time].CurrentMember.PrevMember) `
             && `select {[Measures].[Prev]} on 0, [Time].[1997].Children on 1 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_computed ) ( c_static ) ) cells = c_computed query = c_computed ).
    " the tuple it reads is member navigation; the calculated member that reads it is computed
    cl_abap_unit_assert=>assert_equals( act = planner->get_mark( query-formulas[ 1 ]-expression ) exp = c_static ).
  ENDMETHOD.

  METHOD sets_by_value.
    " the set needs values before the axis exists; its cells are still groups
    plan_query( `select Filter([Store].[Store State].Members, [Measures].[Unit Sales] > 50000) on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_computed ) ) cells = c_relational query = c_computed ).
    plan_query( `select Generate([Store].Children, {[Store].CurrentMember.FirstChild}) on 0 from [ZFMSALES]` ).
    assert_axis_node( c_computed ).
  ENDMETHOD.

  METHOD native_top_count.
    plan_query( `select TopCount([Store].[Store City].Members, 5, [Measures].[Unit Sales]) on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_relational ) ) cells = c_relational query = c_relational ).
    plan_query( `select TopCount([Store].[Store City].Members, 5, [Measures].[Unit Sales] * 2) on 0 from [ZFMSALES]` ).
    assert_axis_node( c_computed ).
    plan_query( `select TopCount([Store].[Store City].Members, 5) on 0 from [ZFMSALES]` ).
    assert_axis_node( c_computed ).
  ENDMETHOD.

  METHOD native_order.
    plan_query( `select Order([Store].[Store State].Members, [Measures].[Unit Sales], BDESC) on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_relational ) ) cells = c_relational query = c_relational ).
    plan_query( `select Head(Order([Store].[Store State].Members, [Store].CurrentMember.OrderKey, BASC), 3) on 0 `
             && `from [ZFMSALES]` ).
    assert_axis_node( c_relational ).
    " hierarchical order and keys of other values are sorted in ABAP
    plan_query( `select Order([Store].[Store State].Members, [Measures].[Unit Sales], DESC) on 0 from [ZFMSALES]` ).
    assert_axis_node( c_computed ).
    plan_query( `select Order([Store].[Store State].Members, [Store].CurrentMember.Name, BASC) on 0 from [ZFMSALES]` ).
    assert_axis_node( c_computed ).
  ENDMETHOD.

  METHOD format_expression.
    " a cell property that is an expression
    plan_query( `with member [Measures].[Sales] as [Measures].[Store Sales], `
             && `FORMAT_STRING = IIf([Measures].[Store Sales] > 1000, "#,##0", "0.00") `
             && `select {[Measures].[Sales]} on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_computed ) ) cells = c_computed query = c_computed ).
    cl_abap_unit_assert=>assert_equals( act = planner->get_mark( query-formulas[ 1 ]-properties[ 1 ]-expression )
                                        exp = c_computed ).
  ENDMETHOD.

  METHOD named_sets.
    plan_query( `with set [Countries] as [Store].[Store Country].Members `
             && `select [Countries] on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_static ) ) cells = c_relational query = c_relational ).
    plan_query( `with set [Big] as Filter([Store].[Store State].Members, [Measures].[Unit Sales] > 50000) `
             && `select [Big] on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_computed ) ) cells = c_relational query = c_computed ).
  ENDMETHOD.

  METHOD visual_totals.
    plan_query( `select VisualTotals({[Store].[USA], [Store].[USA].[CA], [Store].[USA].[OR]}) on 0 from [ZFMSALES]` ).
    assert_plan( axes = VALUE #( ( c_computed ) ) cells = c_computed query = c_computed ).
  ENDMETHOD.

ENDCLASS.
