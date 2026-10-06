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
"! Queries on ZFMSALES with the answers of the reference server: Order, Cast, Aggregate, the set functions, the aggregates, the
"! operators IN, IS, MATCHES, Existing and evaluation errors as cell values.
CLASS ltc_engine DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    METHODS execute
      IMPORTING mdx           TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_engine=>ty_result
      RAISING   zzxxmla1_cx_xmla.
    "! The tuples of the first axis, each as its members' unique names joined by commas.
    METHODS tuples
      IMPORTING result        TYPE zzxxmla1_cl_mdx_engine=>ty_result
      RETURNING VALUE(names)  TYPE string_table.
    "! The values of the cells; an empty cell is null.
    METHODS values
      IMPORTING result        TYPE zzxxmla1_cl_mdx_engine=>ty_result
      RETURNING VALUE(values) TYPE string_table.
    METHODS order_hierarchical FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS order_break FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS order_dependent_members FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS order_constant_key_members FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS order_errors FOR TESTING.
    METHODS cast FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS aggregate FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS evaluation_error_in_cell FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS levels_and_nativize_set FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS filter FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS top_bottom_count FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS range FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS descendants FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS compound_slicer FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS union_except_intersect FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS head_tail_distinct_item FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS count_sum_avg_min_max FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS rank_and_set_to_str FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS hierarchize_calculated_members FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS named_sets_and_generate FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS member_navigation FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS ancestors_and_periods FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS names_and_order_keys FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS in_is_matches FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS existing_and_exists FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS scalar_functions FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS set_functions_of_the_model FOR TESTING RAISING zzxxmla1_cx_xmla.
    METHODS visual_totals_and_dates FOR TESTING RAISING zzxxmla1_cx_xmla.
    "! The result limit (result.limit): a crossjoin larger than it fails before it is built.
    METHODS crossjoin_result_limit FOR TESTING RAISING zzxxmla1_cx_xmla.
    "! The native crossjoin (RolapNativeCrossJoin): the combinations with facts, in hierarchy order.
    METHODS native_crossjoin FOR TESTING RAISING zzxxmla1_cx_xmla.
    "! The multi-variant expansion: a level group of more members than MaxConstraints is still read natively.
    METHODS native_crossjoin_large_level FOR TESTING RAISING zzxxmla1_cx_xmla.
ENDCLASS.

CLASS ltc_engine IMPLEMENTATION.

  METHOD execute.
    result = NEW zzxxmla1_cl_mdx_engine( `` )->execute( zzxxmla1_cl_mdx_parser=>parse( mdx )-query ).
  ENDMETHOD.

  METHOD tuples.
    LOOP AT result-axes[ 1 ]-tuples INTO DATA(tuple).
      APPEND concat_lines_of( table = VALUE string_table( FOR member IN tuple ( member-unique_name ) ) sep = `,` )
          TO names.
    ENDLOOP.
  ENDMETHOD.

  METHOD values.
    values = VALUE #( FOR cell IN result-cells ( COND #( WHEN cell-empty = abap_true THEN `null` ELSE cell-value ) ) ).
  ENDMETHOD.

  METHOD order_hierarchical.
    " ASC / DESC keep the hierarchy: the All member before its children, also when descending. Values and order from
    " The reference server: Time is a TimeDimension, so the axis is evaluated once, with the default member [Time].[1997]
    " (RolapResult.loadSpecialMembers skips it), and the products are sorted by their unit sales of 1997
    DATA(result) = execute( `select Order({[Product.Product Id].[2], [Product.Product Id].[1], `
                         && `[Product.Product Id].[All Product.Product Ids]}, [Measures].[Unit Sales], DESC) `
                         && `on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product.Product Id].[All Product.Product Ids]` )
                                                                  ( `[Product.Product Id].[2]` )
                                                                  ( `[Product.Product Id].[1]` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = values( result ) exp = VALUE string_table( ( `266773` ) ( `171` ) ( `83` ) ) ).
  ENDMETHOD.

  METHOD order_break.
    " BASC breaks the hierarchy: by value only (83, 171, 266773), the All member last
    DATA(result) = execute( `select Order({[Product.Product Id].[2], [Product.Product Id].[1], `
                         && `[Product.Product Id].[All Product.Product Ids]}, [Measures].[Unit Sales], BASC) `
                         && `on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product.Product Id].[1]` )
                                                                  ( `[Product.Product Id].[2]` )
                                                                  ( `[Product.Product Id].[All Product.Product Ids]` ) ) ).
  ENDMETHOD.

  METHOD filter.
    " the tuples in the order of the set whose condition is true in their context (answers of the reference server)
    DATA(result) = execute( `select Filter([Product].[Product Family].Members, [Measures].[Unit Sales] > 30000) `
                         && `on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product].[Food]` ) ( `[Product].[Non-Consumable]` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = values( result ) exp = VALUE string_table( ( `191940` ) ( `50236` ) ) ).
    " IsEmpty: the quarters of the empty year 0 and of 1998 have no sales
    result = execute( `select Filter([Time].[Quarter].Members, NOT IsEmpty([Measures].[Unit Sales])) on 0 `
                   && `from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Time].[1997].[Q1]` ) ( `[Time].[1997].[Q2]` )
                                                                  ( `[Time].[1997].[Q3]` ) ( `[Time].[1997].[Q4]` ) ) ).
    " tuples: the condition sees all their members
    result = execute( `select Filter(CrossJoin({[Store.Store Id].[1], [Store.Store Id].[2]}, `
                   && `{[Product.Product Id].[1], [Product.Product Id].[2]}), `
                   && `[Store.Store Id].CurrentMember.Name = '2') on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Store.Store Id].[2],[Product.Product Id].[1]` )
                                                                  ( `[Store.Store Id].[2],[Product.Product Id].[2]` ) ) ).
  ENDMETHOD.

  METHOD top_bottom_count.
    " answers of the reference server
    DATA(result) = execute( `select TopCount([Product].[Product Department].Members, 3, [Measures].[Unit Sales]) `
                         && `on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product].[Food].[Produce]` )
                                                                  ( `[Product].[Food].[Snack Foods]` )
                                                                  ( `[Product].[Non-Consumable].[Household]` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `37792` ) ( `30545` ) ( `27038` ) ) ).
    " empty values are the smallest: first for BottomCount, last for TopCount, equal ones in the order of the set
    result = execute( `select BottomCount([Product].[Product Family].Members, 2, [Measures].[Unit Sales]) `
                   && `on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product].[]` ) ( `[Product].[Drink]` ) ) ).
    result = execute( `select TopCount({[Time].[1998], [Time].[0], [Time].[1997]}, 2, [Measures].[Unit Sales]) `
                   && `on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Time].[1997]` ) ( `[Time].[1998]` ) ) ).
    " without a value: the head or the tail of the set
    result = execute( `select TopCount([Product].[Product Family].Members, 2) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product].[]` ) ( `[Product].[Drink]` ) ) ).
    result = execute( `select BottomCount([Product].[Product Family].Members, 2) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product].[Food]` ) ( `[Product].[Non-Consumable]` ) ) ).
    " tuples
    result = execute( `select TopCount(CrossJoin({[Store.Store Id].[1], [Store.Store Id].[2]}, `
                   && `{[Product].[Drink], [Product].[Food]}), 3, [Measures].[Unit Sales]) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Store.Store Id].[2],[Product].[Food]` )
                                                                  ( `[Store.Store Id].[2],[Product].[Drink]` )
                                                                  ( `[Store.Store Id].[1],[Product].[Drink]` ) ) ).
  ENDMETHOD.

  METHOD range.
    " answers of the reference server: in hierarchy order whatever the order of the arguments, across parents
    DATA(result) = execute( `select {[Time].[1997].[Q3]:[Time].[1997].[Q1]} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Time].[1997].[Q1]` ) ( `[Time].[1997].[Q2]` )
                                                                  ( `[Time].[1997].[Q3]` ) ) ).
    result = execute( `select {[Time].[1997].[Q1].[3]:[Time].[1997].[Q2].[5]} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Time].[1997].[Q1].[3]` ) ( `[Time].[1997].[Q2].[4]` )
                                                                  ( `[Time].[1997].[Q2].[5]` ) ) ).
    TRY.
        execute( `select {[Time].[1997].[Q1]:[Time].[1997].[Q1].[2]} on 0 from [ZFMSALES]` ).
        cl_abap_unit_assert=>fail( `no error` ).
      CATCH zzxxmla1_cx_mdx_evaluation INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( act = error->error_message exp = `Members must belong to the same level` ).
    ENDTRY.
  ENDMETHOD.

  METHOD descendants.
    " answers of the reference server
    DATA(result) = execute( `select Descendants([Product].[Drink], [Product].[Product Category]) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result ) exp = VALUE string_table(
      ( `[Product].[Drink].[Alcoholic Beverages].[Beer and Wine]` )
      ( `[Product].[Drink].[Beverages].[Carbonated Beverages]` )
      ( `[Product].[Drink].[Beverages].[Drinks]` )
      ( `[Product].[Drink].[Beverages].[Hot Beverages]` )
      ( `[Product].[Drink].[Beverages].[Pure Juice Beverages]` )
      ( `[Product].[Drink].[Dairy].[Dairy]` ) ) ).
    " by depth
    result = execute( `select Descendants([Product].[Drink].[Dairy], 2, SELF_AND_BEFORE) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result ) exp = VALUE string_table(
      ( `[Product].[Drink].[Dairy]` ) ( `[Product].[Drink].[Dairy].[Dairy]` )
      ( `[Product].[Drink].[Dairy].[Dairy].[Milk]` ) ) ).
    " leaves without a depth
    result = execute( `select Descendants([Time].[1997].[Q1], , LEAVES) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result ) exp = VALUE string_table(
      ( `[Time].[1997].[Q1].[1]` ) ( `[Time].[1997].[Q1].[2]` ) ( `[Time].[1997].[Q1].[3]` ) ) ).
    " the member only: itself and all below it
    result = execute( `select Descendants([Product].[Drink].[Dairy]) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = lines( result-axes[ 1 ]-tuples ) exp = 33 ).
    " a set: Generate, each member once, in the order of the set
    result = execute( `select Descendants({[Product].[Drink].[Dairy], [Product].[Drink]}, `
                   && `[Product].[Product Category], BEFORE) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result ) exp = VALUE string_table(
      ( `[Product].[Drink].[Dairy]` ) ( `[Product].[Drink]` ) ( `[Product].[Drink].[Alcoholic Beverages]` )
      ( `[Product].[Drink].[Beverages]` ) ) ).
  ENDMETHOD.

  METHOD order_dependent_members.
    " the key depends on Store only: tuples with the same store compare as equal and keep their order
    DATA(result) = execute( `select Order(CrossJoin({[Store.Store Id].[1], [Store.Store Id].[2]}, `
                         && `{[Product.Product Id].[1], [Product.Product Id].[2]}), `
                         && `[Store.Store Id].CurrentMember.Name, DESC) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Store.Store Id].[2],[Product.Product Id].[1]` )
                                                                  ( `[Store.Store Id].[2],[Product.Product Id].[2]` )
                                                                  ( `[Store.Store Id].[1],[Product.Product Id].[1]` )
                                                                  ( `[Store.Store Id].[1],[Product.Product Id].[2]` ) ) ).
  ENDMETHOD.

  METHOD order_constant_key_members.
    " the constant members of the key are set first and the key is the cell of the context (ContextCalc): the
    " products are then compared by their own unit sales
    DATA(result) = execute( `select Order(CrossJoin({[Store.Store Id].[All Store.Store Ids]}, `
                         && `{[Product.Product Id].[1], [Product.Product Id].[2]}), `
                         && `([Measures].[Unit Sales], [Product.Product Id].[1]), DESC) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals(
      act = tuples( result )
      exp = VALUE string_table( ( `[Store.Store Id].[All Store.Store Ids],[Product.Product Id].[2]` )
                                ( `[Store.Store Id].[All Store.Store Ids],[Product.Product Id].[1]` ) ) ).
  ENDMETHOD.

  METHOD order_errors.
    " text from the reference server
    TRY.
        execute( `select Order({[Product.Product Id].[1]}, [Measures].[Unit Sales], PRE) on 0 from [ZFMSALES]` ).
        cl_abap_unit_assert=>fail( `no error` ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( act = error->description exp = `Allowed values are: {ASC, DESC, BASC, BDESC}` ).
    ENDTRY.
  ENDMETHOD.

  METHOD cast.
    " values and types from the reference server: a numeric literal is written as BigDecimal, intValue truncates
    DATA(result) = execute( `with member measures.a as cast(1.50 as string) member measures.b as cast('7' as integer) `
                         && `member measures.c as cast(2.7 as integer) member measures.d as cast('tRue' as boolean) `
                         && `select {measures.a, measures.b, measures.c, measures.d} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `1.50` ) ( `7` ) ( `2` ) ( `true` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = VALUE string_table( FOR cell IN result-cells ( cell-value_type ) )
                                        exp = VALUE string_table( ( `xsd:string` ) ( `xsd:integer` ) ( `xsd:integer` )
                                                                  ( `xsd:boolean` ) ) ).
    " Integer.parseInt fails: the query fails (NumberFormatException)
    TRY.
        execute( `with member measures.x as cast('1.5' as integer) select measures.x on 0 from [ZFMSALES]` ).
        cl_abap_unit_assert=>fail( `no error` ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( act = error->fault_code exp = `SOAP-ENV:Server.00HSBD02` ).
        cl_abap_unit_assert=>assert_equals( act = error->description exp = `For input string: "1.5"` ).
    ENDTRY.
  ENDMETHOD.

  METHOD aggregate.
    " the measure's aggregator rolls up: Fact Count (count) is summed; Aggregate({}) is null
    DATA(result) = execute( `with member [Product.Product Id].[x] as `
                         && `Aggregate({[Product.Product Id].[1], [Product.Product Id].[2]}) `
                         && `member [Product.Product Id].[e] as Aggregate({}) `
                         && `select {[Measures].[Unit Sales], [Measures].[Fact Count]} on 0, `
                         && `{[Product.Product Id].[x], [Product.Product Id].[e]} on 1 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `254` ) ( `82` ) ( `null` ) ( `null` ) ) ).
  ENDMETHOD.

  METHOD compound_slicer.
    " answers of the reference server (with scripts/patches/compound-slicer.patch) and of AccessControlTest:
    " the cells are rolled up over the tuples of the slicer, which stay the slicer axis
    DATA(result) = execute( `select {[Measures].[Unit Sales]} on columns, {[Product].[Food].[Baked Goods].[Bread]} `
                         && `on rows from [ZFMSALES] where {[Store].[USA].[CA], [Store].[USA].[OR]}` ).
    cl_abap_unit_assert=>assert_equals( act = values( result ) exp = VALUE string_table( ( `4163` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( result-slicer ) exp = 2 ).
    " tuples; the axis is evaluated with the placeholders in the context
    result = execute( `select [Measures].[Unit Sales] on columns, Filter([Time].[1997].Children, `
                   && `[Measures].[Unit Sales] < 12335) on rows from [ZFMSALES] `
                   && `where {([Product].[Drink],[Store].[USA].[CA]),([Product].[Food],[Store].[USA].[OR])}` ).
    cl_abap_unit_assert=>assert_equals( act = result-axes[ 2 ]-tuples[ 1 ][ 1 ]-unique_name exp = `[Time].[1997].[Q2]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result ) exp = VALUE string_table( ( `12334` ) ) ).
    " SCOPED: the placeholder (cube scope) expands before a calculation with Aggregate, the measure is calculated
    result = execute( `with member [Measures].[TotalVal] as 'Aggregate(Filter({[Store].[Store City].members}, `
                   && `[Measures].[Unit Sales] > 1000))' select [Measures].[TotalVal] on 0, [Product].[Drink] on 1 `
                   && `from [ZFMSALES] where {[Time].[1997].[Q1], [Time].[1997].[Q2]}` ).
    cl_abap_unit_assert=>assert_equals( act = result-cells[ 1 ]-value
                                        exp = `olap4abap.EvaluationException: `
                                           && `Could not find an aggregator in the current evaluation context` ).
    " CurrentMember of a hierarchy with several slicer members
    TRY.
        execute( `with member [Measures].[x] as '([Time].CurrentMember, [Measures].[Unit Sales])' `
              && `select [Measures].[x] on 0 from [ZFMSALES] where {[Time].[1997].[Q4], [Time].[1997].[Q3]}` ).
        cl_abap_unit_assert=>fail( `no error` ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( act = error->fault_code exp = `SOAP-ENV:Server.00HSBD02` ).
    ENDTRY.
  ENDMETHOD.

  METHOD evaluation_error_in_cell.
    " the error is the value of its cell only; the other cells and the query go on
    DATA(result) = execute( `with member [Measures].[Bar] as cast(123 as string) `
                         && `member [Measures].[Foo] as [Measures].[Bar] / 2 `
                         && `select {[Measures].[Foo], [Measures].[Unit Sales]} on 0 from [ZFMSALES]` ).
    DATA(text) = `olap4abap.EvaluationException: Expected value of type NUMERIC; got value '123' (STRING)`.
    cl_abap_unit_assert=>assert_equals( act = result-cells[ 1 ]-value exp = text ).
    cl_abap_unit_assert=>assert_equals( act = result-cells[ 1 ]-value_type exp = `xsd:string` ).
    cl_abap_unit_assert=>assert_equals( act = result-cells[ 1 ]-formatted exp = |#ERR: { text }| ).
    cl_abap_unit_assert=>assert_equals( act = result-cells[ 2 ]-value exp = `266773` ).
  ENDMETHOD.

  METHOD levels_and_nativize_set.
    " Levels(0) is the (All) level; NativizeSet below its threshold is the set itself
    DATA(result) = execute( `select NativizeSet({[Store].Levels(0).Members}) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result ) exp = VALUE string_table( ( `[Store].[All Stores]` ) ) ).
    result = execute( `select [Store].Levels("Store Country").Members on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = tuples( execute( `select [Store].Levels(1).Members on 0 from [ZFMSALES]` ) ) ).
    " an evaluation error on an axis fails the query, as in the reference server
    TRY.
        execute( `select [Store].Levels(5).Members on 0 from [ZFMSALES]` ).
        cl_abap_unit_assert=>fail( `no error` ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( act = error->fault_code exp = `SOAP-ENV:Server.00HSBD02` ).
        cl_abap_unit_assert=>assert_equals( act = error->fault_string exp = `XMLA MDX execute failed Index '5' out of bounds` ).
    ENDTRY.
  ENDMETHOD.

  METHOD union_except_intersect.
    " answers of the reference server; Union removes duplicates unless ALL
    DATA(result) = execute( `select Union({[Product].[Drink], [Product].[Food]}, `
                         && `{[Product].[Food], [Product].[Non-Consumable]}) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product].[Drink]` ) ( `[Product].[Food]` )
                                                                  ( `[Product].[Non-Consumable]` ) ) ).
    result = execute( `select Union({[Product].[Drink], [Product].[Food]}, `
                   && `{[Product].[Food], [Product].[Non-Consumable]}, ALL) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = lines( result-axes[ 1 ]-tuples ) exp = 4 ).
    TRY.
        execute( `select Union({[Product].[Drink]}, {[Store].[USA]}) on 0 from [ZFMSALES]` ).
        cl_abap_unit_assert=>fail( `no error` ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( act = error->fault_string
                                            exp = `XMLA SOAP Body processing error Expressions must have the same hierarchy` ).
    ENDTRY.
    " Except and set - set
    result = execute( `select [Product].[Product Family].Members - {[Product].[Drink]} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product].[]` ) ( `[Product].[Food]` )
                                                                  ( `[Product].[Non-Consumable]` ) ) ).
    " Intersect keeps the duplicates of the first set only with ALL
    result = execute( `select Intersect({[Product].[Drink], [Product].[Food], [Product].[Drink]}, `
                   && `{[Product].[Drink], [Product].[Non-Consumable]}) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result ) exp = VALUE string_table( ( `[Product].[Drink]` ) ) ).
    result = execute( `select Intersect({[Product].[Drink], [Product].[Food], [Product].[Drink]}, `
                   && `{[Product].[Drink]}, ALL) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = lines( result-axes[ 1 ]-tuples ) exp = 2 ).
  ENDMETHOD.

  METHOD head_tail_distinct_item.
    DATA(result) = execute( `select Head([Product].[Product Family].Members, 2) on 0, `
                         && `Tail([Store].[Store Country].Members) on 1 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product].[]` ) ( `[Product].[Drink]` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = result-axes[ 2 ]-tuples[ 1 ][ 1 ]-unique_name exp = `[Store].[USA]` ).
    result = execute( `select Distinct({[Product].[Drink], [Product].[Food], [Product].[Drink]}) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product].[Drink]` ) ( `[Product].[Food]` ) ) ).
    " Item of a set by index or name, of a tuple by index
    result = execute( `with member [Measures].[i1] as '([Product].[Product Family].Members.Item(2), `
                   && `[Measures].[Unit Sales])' `
                   && `member [Measures].[i2] as '([Product].[Product Family].Members.Item("Drink"), `
                   && `[Measures].[Unit Sales])' `
                   && `member [Measures].[i3] as '(([Product].[Food], [Time].[1997]).Item(0), [Measures].[Unit Sales])' `
                   && `select {[Measures].[i1], [Measures].[i2], [Measures].[i3]} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `191940` ) ( `24597` ) ( `191940` ) ) ).
    result = execute( `select {CrossJoin({[Product].[Drink]}, {[Time].[1997], [Time].[1998]}).Item(1)} on 0 `
                   && `from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product].[Drink],[Time].[1998]` ) ) ).
  ENDMETHOD.

  METHOD count_sum_avg_min_max.
    " EXCLUDEEMPTY counts the combinations with sales (1997 of three families); Sum without a value sums the cells,
    " a set without values is null
    DATA(result) = execute(
      `with member [Measures].[c1] as 'Count([Product].[Product Department].Members)' `
   && `member [Measures].[c2] as 'Count(CrossJoin([Product].[Product Family].Members, [Time].[Year].Members), `
   && `EXCLUDEEMPTY)' `
   && `member [Measures].[c3] as '[Product].[Product Family].Members.Count' `
   && `member [Measures].[s] as 'Sum([Product].[Product Family].Members)' `
   && `member [Measures].[a] as 'Avg([Time].[1997].Children, [Measures].[Unit Sales])' `
   && `member [Measures].[mi] as 'Min([Time].[1997].Children, [Measures].[Unit Sales])' `
   && `member [Measures].[ma] as 'Max([Time].[1997].Children, [Measures].[Unit Sales])' `
   && `member [Measures].[e] as 'Sum({[Time].[1998]}, [Measures].[Unit Sales])' `
   && `select {[Measures].[c1], [Measures].[c2], [Measures].[c3], [Measures].[s], [Measures].[a], [Measures].[mi], `
   && `[Measures].[ma], [Measures].[e]} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `24` ) ( `3` ) ( `4` ) ( `266773` ) ( `66693.25` )
                                                                  ( `62610` ) ( `72024` ) ( `null` ) ) ).
  ENDMETHOD.

  METHOD rank_and_set_to_str.
    " Rank without a value: the position in the set (0 if not in it); with one: by value descending
    DATA(result) = execute(
      `with member [Measures].[r2] as 'Rank([Product].CurrentMember, [Product].[Product Family].Members)' `
   && `member [Measures].[r3] as 'Rank([Product].CurrentMember, [Product].[Product Family].Members, `
   && `[Measures].[Unit Sales])' `
   && `select {[Measures].[r2], [Measures].[r3]} on 0, `
   && `{[Product].[Product Family].Members, [Product].[All Products]} on 1 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `1` ) ( `4` ) ( `2` ) ( `3` ) ( `3` ) ( `1` )
                                                                  ( `4` ) ( `2` ) ( `0` ) ( `1` ) ) ).
    " a tuple outside the set: ranked by its value among the set's, a null value after all
    result = execute(
      `with member [Measures].[r3] as 'Rank([Product].CurrentMember, {[Product].[Drink], [Product].[Non-Consumable]}, `
   && `[Measures].[Unit Sales])' `
   && `select {[Measures].[r3]} on 0, [Product].[Product Family].Members on 1 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `3` ) ( `2` ) ( `1` ) ( `1` ) ) ).
    result = execute(
      `with member [Measures].[t1] as 'SetToStr({[Product].[Drink], [Product].[Food]})' `
   && `member [Measures].[t2] as 'SetToStr(CrossJoin({[Product].[Drink]}, {[Time].[1997], [Time].[1998]}))' `
   && `member [Measures].[t3] as 'SetToStr({})' `
   && `select {[Measures].[t1], [Measures].[t2], [Measures].[t3]} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals(
      act = values( result )
      exp = VALUE string_table( ( `{[Product].[Drink], [Product].[Food]}` )
                                ( `{([Product].[Drink], [Time].[1997]), ([Product].[Drink], [Time].[1998])}` )
                                ( `{}` ) ) ).
  ENDMETHOD.

  METHOD hierarchize_calculated_members.
    " a calculated member after its stored siblings and their descendants, calculated siblings by name (the reference server)
    DATA(result) = execute( `with member [Time].[1997].[Q1].[xxx] as '1' member [Time].[1997].[Q1].[aaa] as '2' `
                         && `select Hierarchize({[Time].[1997].[Q1].[xxx], [Time].[1997].[Q2], `
                         && `[Time].[1997].[Q1].[aaa], [Time].[1997].[Q1], [Time].[1997].[Q1].[3], [Time].[1997]}) `
                         && `on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Time].[1997]` ) ( `[Time].[1997].[Q1]` )
                                                                  ( `[Time].[1997].[Q1].[3]` )
                                                                  ( `[Time].[1997].[Q1].[aaa]` )
                                                                  ( `[Time].[1997].[Q1].[xxx]` )
                                                                  ( `[Time].[1997].[Q2]` ) ) ).
  ENDMETHOD.

  METHOD named_sets_and_generate.
    " a named set is evaluated in the context of the slicer (answers of the reference server)
    DATA(result) = execute( `with set [T] as 'TopCount([Product].[Product Department].Members, 2, `
                         && `[Measures].[Unit Sales])' select [T] on 0 from [ZFMSALES] where [Time].[1997].[Q2]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product].[Food].[Produce]` )
                                                                  ( `[Product].[Food].[Snack Foods]` ) ) ).
    cl_abap_unit_assert=>assert_equals( act = values( result ) exp = VALUE string_table( ( `8908` ) ( `7009` ) ) ).
    " CurrentOrdinal and Current follow the iteration of Filter and Generate
    result = execute( `with set [S] as [Product].[Product Family].Members `
                   && `select Filter([S], [S].CurrentOrdinal = 1) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result ) exp = VALUE string_table( ( `[Product].[Drink]` ) ) ).
    result = execute( `with set [S] as [Product].[Product Family].Members `
                   && `member [Measures].[o] as 'Generate([S], CAST([S].CurrentOrdinal AS STRING) || [S].Current.Name, ",")' `
                   && `select {[Measures].[o]} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `0,1Drink,2Food,3Non-Consumable` ) ) ).
    " Generate(set, numeric, delimiter): the numbers as Str writes them (answers of the reference server)
    result = execute( `with member [Measures].[c] as 'Generate(Ascendants([Product].[Drink].[Dairy]), `
                   && `[Product].CurrentMember.Children.Count, "|")' `
                   && `member [Measures].[d] as 'Generate({[Product].[Drink], [Product].[Food]}, `
                   && `-[Measures].[Unit Sales] / 2, ",")' `
                   && `member [Measures].[e] as 'Generate({[Product].[Drink]}, [Measures].[Unit Sales] / 0, ",")' `
                   && `select {[Measures].[c], [Measures].[d], [Measures].[e]} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( ` 1| 3| 4` ) ( `-12298.5,-95970.0` )
                                                                  ( ` Infinity` ) ) ).
    " Generate: each tuple once, unless ALL
    result = execute( `select Generate({[Product].[Drink], [Product].[Food]}, `
                   && `{[Product].CurrentMember.Children.Item(0), [Product].[Drink]}, ALL) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product].[Drink].[Alcoholic Beverages]` )
                                                                  ( `[Product].[Drink]` )
                                                                  ( `[Product].[Food].[Baked Goods]` )
                                                                  ( `[Product].[Drink]` ) ) ).
    result = execute( `select Generate({[Product].[Drink], [Product].[Food]}, `
                   && `{[Product].CurrentMember.Children.Item(0), [Product].[Drink]}) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = lines( result-axes[ 1 ]-tuples ) exp = 3 ).
    " an alias in the call around its AS
    result = execute( `select {[Product].[Product Family].Members as t, t.Item(1)} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = lines( result-axes[ 1 ]-tuples ) exp = 5 ).
    cl_abap_unit_assert=>assert_equals( act = result-axes[ 1 ]-tuples[ 5 ][ 1 ]-unique_name exp = `[Product].[Drink]` ).
  ENDMETHOD.

  METHOD member_navigation.
    " answers of the reference server: {} leaves out the null member (the All member's parent, the member after the last)
    DATA(result) = execute( `select {[Product].[All Products].Parent, [Product].[Drink].Parent, `
                         && `[Product].[Drink].FirstChild, [Product].[Drink].LastChild, [Product].[Food].FirstSibling, `
                         && `[Product].[Food].LastSibling, [Product].[Food].NextMember, [Product].[Food].PrevMember, `
                         && `[Product].[Non-Consumable].NextMember} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product].[All Products]` )
                                                                  ( `[Product].[Drink].[Alcoholic Beverages]` )
                                                                  ( `[Product].[Drink].[Dairy]` ) ( `[Product].[]` )
                                                                  ( `[Product].[Non-Consumable]` )
                                                                  ( `[Product].[Non-Consumable]` )
                                                                  ( `[Product].[Drink]` ) ) ).
    " Lead and Lag move along the level, across parents
    result = execute( `select {[Time].[1997].[Q1].[3].Lead(1), [Time].[1997].[Q1].[3].Lag(3), `
                   && `[Time].[1997].[Q1].Lag(-2), [Time].[1997].[Q1].[1].Lead(30)} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Time].[1997].[Q2].[4]` ) ( `[Time].[0].[].[0]` )
                                                                  ( `[Time].[1997].[Q3]` ) ) ).
    result = execute( `select {[Product].[Drink].Siblings, [Product].[All Products].Siblings} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = lines( result-axes[ 1 ]-tuples ) exp = 5 ).
    " a cell with a null member is empty
    result = execute( `with member [Measures].[y] as 'IsEmpty(([Product].[All Products].Parent, `
                   && `[Measures].[Unit Sales]))' select {[Measures].[y]} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result ) exp = VALUE string_table( ( `true` ) ) ).
  ENDMETHOD.

  METHOD ancestors_and_periods.
    DATA(result) = execute( `select {Ancestor([Store].[USA].[CA].[Los Angeles], [Store].[Store Country]), `
                         && `Ancestor([Store].[USA].[CA].[Los Angeles], 2), Ancestor([Store].[USA].[CA].[Los Angeles], 5), `
                         && `Ancestor([Store].[USA], [Store].[Store City])} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Store].[USA]` ) ( `[Store].[USA]` ) ) ).
    result = execute( `select Ascendants([Store].[USA].[CA].[Los Angeles]) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Store].[USA].[CA].[Los Angeles]` )
                                                                  ( `[Store].[USA].[CA]` ) ( `[Store].[USA]` )
                                                                  ( `[Store].[All Stores]` ) ) ).
    result = execute( `with member [Measures].[p1] as 'ParallelPeriod([Time].[Year], 1, [Time].[1998].[Q2].[5]).UniqueName' `
                   && `member [Measures].[p2] as 'ParallelPeriod([Time].[Quarter], 2, [Time].[1997].[Q3].[8]).UniqueName' `
                   && `member [Measures].[p4] as 'ParallelPeriod().UniqueName' `
                   && `member [Measures].[p5] as 'ParallelPeriod([Time].[Year], 3).UniqueName' `
                   && `member [Measures].[p6] as 'SetToStr(PeriodsToDate())' `
                   && `select {[Measures].[p1], [Measures].[p2], [Measures].[p4], [Measures].[p5], [Measures].[p6]} on 0 `
                   && `from [ZFMSALES] where [Time].[1997].[Q3].[8]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `[Time].[1997].[Q2].[5]` ) ( `[Time].[1997].[Q1].[2]` )
                                                                  ( `[Time].[1997].[Q2].[5]` ) ( `[Time].[#null]` )
                                                                  ( `{[Time].[1997].[Q3].[7], [Time].[1997].[Q3].[8]}` ) ) ).
    TRY.
        execute( `with member [Measures].[p] as 'ParallelPeriod([Time].[Year], 1, [Product].[Drink]).UniqueName' `
              && `select {[Measures].[p]} on 0 from [ZFMSALES]` ).
        cl_abap_unit_assert=>fail( `no error` ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( act = error->fault_string
                                            exp = `XMLA MDX execute failed olap4abap Error:The member '[Product].[Drink]' `
                                               && `is not in the same hierarchy as the level '[Time].[Year]'.` ).
    ENDTRY.
  ENDMETHOD.

  METHOD names_and_order_keys.
    DATA(result) = execute(
      `with member [Measures].[u] as '[Product].CurrentMember.Parent.UniqueName' `
   && `member [Measures].[c] as '[Product].CurrentMember.Caption' `
   && `member [Measures].[l] as '[Product].CurrentMember.Level.UniqueName' `
   && `member [Measures].[d] as '[Product].CurrentMember.Dimension.UniqueName' `
   && `select {[Measures].[u], [Measures].[c], [Measures].[l], [Measures].[d]} on 0, `
   && `{[Product].[All Products], [Product].[Drink]} on 1 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `[Product].[#null]` ) ( `All Products` )
                                                                  ( `[Product].[(All)]` ) ( `[Product]` )
                                                                  ( `[Product].[All Products]` ) ( `Drink` )
                                                                  ( `[Product].[Product Family]` ) ( `[Product]` ) ) ).
    " Unique_Name is the reference's synonym of <Member>.UniqueName (Excel sends it; the reference server fails it)
    result = execute( `with member [Measures].[u] as '[Product].CurrentMember.Unique_Name' `
                   && `select {[Measures].[u]} on 0, {[Product].[Drink]} on 1 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `[Product].[Drink]` ) ) ).
    " OrderKey compares keys: strings ignoring case first
    result = execute( `with member [Measures].[k] as 'SetToStr(Order([Store].[Store State].Members, `
                   && `[Store].CurrentMember.OrderKey, BDESC))' select {[Measures].[k]} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals(
      act = values( result )
      exp = VALUE string_table( ( `{[Store].[Mexico].[Zacatecas], [Store].[Mexico].[Yucatan], [Store].[USA].[WA], `
                               && `[Store].[Mexico].[Veracruz], [Store].[USA].[OR], [Store].[Mexico].[Jalisco], `
                               && `[Store].[Mexico].[Guerrero], [Store].[Mexico].[DF], [Store].[USA].[CA], `
                               && `[Store].[Canada].[BC]}` ) ) ).
  ENDMETHOD.

  METHOD in_is_matches.
    " IN, NOT IN (InUdf: by unique name), MATCHES, NOT MATCHES (MatchesUdf: Java's regular expressions); answers of
    " The reference server
    DATA(result) = execute( `select Filter([Product].[Product Family].Members, [Product].CurrentMember IN `
                         && `{[Product].[Food], [Product].[Drink].[Dairy]}) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result ) exp = VALUE string_table( ( `[Product].[Food]` ) ) ).
    result = execute( `select Filter([Product].[Product Family].Members, [Product].CurrentMember NOT IN `
                   && `{[Product].[Food]}) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product].[]` ) ( `[Product].[Drink]` )
                                                                  ( `[Product].[Non-Consumable]` ) ) ).
    result = execute( `select Filter([Product].[Product Family].Members, `
                   && `[Product].CurrentMember.Caption MATCHES '(?i)d.*') on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result ) exp = VALUE string_table( ( `[Product].[Drink]` ) ) ).
    result = execute( `select Filter([Product].[Product Family].Members, `
                   && `[Product].CurrentMember.Caption NOT MATCHES 'D.*') on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product].[]` ) ( `[Product].[Food]` )
                                                                  ( `[Product].[Non-Consumable]` ) ) ).
    " \Q...\E quotes its characters
    result = execute( `select Filter([Product].[Product Family].Members, `
                   && `[Product].CurrentMember.Caption MATCHES '.*\Qn-C\E.*' OR `
                   && `[Product].CurrentMember.Caption MATCHES '\Q.*\E') on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Product].[Non-Consumable]` ) ) ).
    " IS: the same member or level; IS NULL: the null member
    result = execute( `with member [Measures].[x] as 'IIf([Product].CurrentMember IS [Product].[Food], 1, 0)' `
                   && `member [Measures].[y] as 'IIf([Product].CurrentMember.Parent IS NULL, 1, 0)' `
                   && `member [Measures].[z] as 'IIf([Product].CurrentMember.Level IS [Product].[Product Family], 1, 0)' `
                   && `select {[Measures].[x], [Measures].[y], [Measures].[z]} on 0, `
                   && `{[Product].[All Products], [Product].[Food], [Product].[Food].[Dairy]} on 1 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `0` ) ( `1` ) ( `0` ) ( `1` ) ( `0` ) ( `1` )
                                                                  ( `0` ) ( `0` ) ( `0` ) ) ).
    " IS EMPTY of a member, IS of tuples, IS NULL of the parent of the null member
    result = execute( `with member [Measures].[e] as 'IIf([Measures].[Unit Sales] IS EMPTY, 1, 0)' `
                   && `member [Measures].[t] as 'IIf(([Product].CurrentMember, [Store].CurrentMember) IS `
                   && `([Product].[Food], [Store].[All Stores]), 1, 0)' `
                   && `member [Measures].[n] as 'IIf([Product].CurrentMember.Parent.Parent IS NULL, 1, 0)' `
                   && `select {[Measures].[e], [Measures].[t], [Measures].[n]} on 0, `
                   && `{[Product].[All Products], [Product].[Food], [Product].[]} on 1 from [ZFMSALES] `
                   && `where [Time].[1997].[Q1]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `0` ) ( `0` ) ( `1` ) ( `0` ) ( `1` ) ( `1` )
                                                                  ( `1` ) ( `0` ) ( `1` ) ) ).
  ENDMETHOD.

  METHOD existing_and_exists.
    " Existing: the members on the hierarchy chain of the context member (ancestors, descendants, itself); answers of
    " The reference server
    DATA(result) = execute(
      `with member [Measures].[c] as 'Count(Existing [Product].[Product Department].Members)' `
   && `member [Measures].[s] as `
   && `'SetToStr(Existing {[Product].[Drink].[Dairy], [Product].[Food].[Dairy], [Product].[Food]})' `
   && `select {[Measures].[c], [Measures].[s]} on 0, `
   && `{[Product].[All Products], [Product].[Drink], [Product].[Food].[Dairy].[Dairy]} on 1 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals(
      act = values( result )
      exp = VALUE string_table( ( `24` ) ( `{[Product].[Drink].[Dairy], [Product].[Food].[Dairy], [Product].[Food]}` )
                                ( `3` ) ( `{[Product].[Drink].[Dairy]}` )
                                ( `1` ) ( `{[Product].[Food].[Dairy], [Product].[Food]}` ) ) ).
    " a compound slicer: on the chain of one of its members
    result = execute( `with member [Measures].[s] as 'SetToStr(Existing [Product].[Product Family].Members)' `
                   && `select {[Measures].[s]} on 0 from [ZFMSALES] `
                   && `where {[Product].[Drink].[Dairy], [Product].[Food].[Dairy]}` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `{[Product].[Drink], [Product].[Food]}` ) ) ).
    " ... of several hierarchies: the reference finds the second hierarchy in no tuple, so nothing exists
    result = execute( `with member [Measures].[s] as 'SetToStr(Existing [Product].[Product Family].Members)' `
                   && `select {[Measures].[s]} on 0 from [ZFMSALES] `
                   && `where {([Product].[Drink].[Dairy], [Store].[USA].[CA]), `
                   && `([Product].[Food].[Dairy], [Store].[USA].[OR])}` ).
    cl_abap_unit_assert=>assert_equals( act = values( result ) exp = VALUE string_table( ( `{}` ) ) ).
    " Exists: with a tuple of the second set; a hierarchy not in the first set is compared with its default member
    result = execute(
      `with member [Measures].[s] as `
   && `'SetToStr(Exists([Product].[Product Family].Members, {[Product].[Drink].[Dairy], [Product].[Food]}))' `
   && `member [Measures].[t] as `
   && `'SetToStr(Exists(CrossJoin({[Store].[USA].[CA], [Store].[Mexico]}, {[Product].[Food]}), {[Store].[USA]}))' `
   && `select {[Measures].[s], [Measures].[t]} on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `{[Product].[Drink], [Product].[Food]}` )
                                                                  ( `{([Store].[USA].[CA], [Product].[Food])}` ) ) ).
  ENDMETHOD.

  METHOD scalar_functions.
    " LastNonEmpty, Format, Mod (towards negative infinity), CoalesceEmpty, CASE; answers of the reference server
    DATA(result) = execute(
      `with member [Measures].[l] as 'LastNonEmpty([Time].[1997].[Q4].Children, [Measures].[Unit Sales]).UniqueName' `
   && `member [Measures].[f] as 'Format([Measures].[Unit Sales], "#,##0.0")' `
   && `member [Measures].[m] as 'Mod(17, 5) + Mod(-7, 3)' `
   && `member [Measures].[c] as 'CoalesceEmpty(([Measures].[Unit Sales], [Time].[1998]), 7)' `
   && `member [Measures].[k] as 'Case [Product].CurrentMember.Name When "Drink" Then "d" When "Food" Then "f" `
   && `Else "x" End' `
   && `select {[Measures].[l], [Measures].[f], [Measures].[m], [Measures].[c], [Measures].[k]} on 0, `
   && `{[Product].[Drink], [Product].[Non-Consumable]} on 1 from [ZFMSALES] `
   && `where [Store].[USA].[OR].[Portland].[Store 11]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `[Time].[1997].[Q4].[12]` ) ( `2,371.0` ) ( `4` )
                                                                  ( `7` ) ( `d` )
                                                                  ( `[Time].[1997].[Q4].[12]` ) ( `5,076.0` ) ( `4` )
                                                                  ( `7` ) ( `x` ) ) ).
    " CASE WHEN, CInt of null is null (JavaFunDef): the sum of the months up to September (MonitorTest)
    result = execute( `WITH MEMBER [Measures].[Foo] AS [Measures].[Unit Sales] + case when [Measures].[Unit Sales] > 0 `
                   && `then CInt( ([Measures].[Foo], [Time].PrevMember) ) end `
                   && `SELECT [Measures].[Foo] on 0 from [ZFMSALES] where [Time].[1997].[Q3].[9]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result ) exp = VALUE string_table( ( `194749` ) ) ).
    " Properties: PARENT_UNIQUE_NAME (null for the All member), MEMBER_TYPE, LEVEL_NUMBER, CHILDREN_CARDINALITY
    result = execute(
      `with member [Measures].[p] as '[Product].CurrentMember.Properties("PARENT_UNIQUE_NAME")' `
   && `member [Measures].[t] as '[Product].CurrentMember.Properties("MEMBER_TYPE")' `
   && `member [Measures].[n] as '[Product].CurrentMember.Properties("LEVEL_NUMBER")' `
   && `member [Measures].[c] as '[Product].CurrentMember.Properties("CHILDREN_CARDINALITY")' `
   && `select {[Measures].[p], [Measures].[t], [Measures].[n], [Measures].[c]} on 0, `
   && `{[Product].[Drink], [Product].[All Products]} on 1 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `[Product].[All Products]` ) ( `1` ) ( `1` ) ( `3` )
                                                                  ( `null` ) ( `2` ) ( `0` ) ( `4` ) ) ).
  ENDMETHOD.

  METHOD set_functions_of_the_model.
    " DrilldownLevel: the children after the whole set (the reference's drill), INCLUDE_CALC_MEMBERS; answers of
    " The reference server
    DATA(result) = execute( `select DrilldownLevel({[Store].[Canada], [Store].[Mexico]}) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Store].[Canada]` ) ( `[Store].[Mexico]` )
                                                                  ( `[Store].[Canada].[BC]` ) ( `[Store].[Mexico].[DF]` )
                                                                  ( `[Store].[Mexico].[Guerrero]` )
                                                                  ( `[Store].[Mexico].[Jalisco]` )
                                                                  ( `[Store].[Mexico].[Veracruz]` )
                                                                  ( `[Store].[Mexico].[Yucatan]` )
                                                                  ( `[Store].[Mexico].[Zacatecas]` ) ) ).
    result = execute( `with member [Store].[USA].[calc] as '1' `
                   && `select DrilldownLevel({[Store].[USA]}, , , INCLUDE_CALC_MEMBERS) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Store].[USA]` ) ( `[Store].[USA].[CA]` )
                                                                  ( `[Store].[USA].[OR]` ) ( `[Store].[USA].[WA]` )
                                                                  ( `[Store].[USA].[calc]` ) ) ).
    result = execute( `select DrilldownLevel({([Store].[USA], [Product].[Drink])}, , 1) on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals(
      act = tuples( result )
      exp = VALUE string_table( ( `[Store].[USA],[Product].[Drink]` )
                                ( `[Store].[USA],[Product].[Drink].[Alcoholic Beverages]` )
                                ( `[Store].[USA],[Product].[Drink].[Beverages]` )
                                ( `[Store].[USA],[Product].[Drink].[Dairy]` ) ) ).
    " AddCalculatedMembers and CalculatedChild: the calculated child of the current member (FunctionTest)
    result = execute(
      `with member [Product].[All Products].[Drink].[Calculated Child] as '[Product].[All Products].[Drink].[Alcoholic Beverages]' `
   && `member [Product].[All Products].[Non-Consumable].[Calculated Child] as `
   && `'[Product].[All Products].[Non-Consumable].[Carousel]' `
   && `member [Measures].[a] as '([Measures].[Unit Sales], `
   && `AddCalculatedMembers([Product].currentmember.children).Item("Calculated Child"))' `
   && `member [Measures].[b] as '([Measures].[Unit Sales], [Product].currentmember.CalculatedChild("Calculated Child"))' `
   && `select {[Measures].[a], [Measures].[b]} on 0, {[Product].[Drink], [Product].[Non-Consumable]} on 1 `
   && `from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `6838` ) ( `6838` ) ( `841` ) ( `841` ) ) ).
    " Parameter: no value is set, so the default; a set of the type's hierarchy
    result = execute( `select {[Measures].[Unit Sales]} ON 0, `
                   && `Parameter("Foo", [Time], {[Time].[1997].[Q2].[5], [Time].[1997].[Q3]}, "Foo") ON 1 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result ) exp = VALUE string_table( ( `21081` ) ( `65848` ) ) ).
  ENDMETHOD.

  METHOD visual_totals_and_dates.
    " VisualTotals: a member followed by its descendants totals them, with the caption of the pattern (** an asterisk)
    DATA(result) = execute( `with member [Measures].[c] as '[Product].CurrentMember.Caption' `
                         && `member [Measures].[n] as '[Product].CurrentMember.Name' `
                         && `select {[Measures].[Unit Sales], [Measures].[c], [Measures].[n]} on 0, `
                         && `VisualTotals({[Product].[Drink], [Product].[Drink].[Dairy], [Product].[Drink].[Beverages]}, `
                         && `'** Total - *') on 1 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `17759` ) ( `* Total - Drink` ) ( `Drink` )
                                                                  ( `4186` ) ( `Dairy` ) ( `Dairy` )
                                                                  ( `13573` ) ( `Beverages` ) ( `Beverages` ) ) ).
    " ... also of the All member, which is the default member (FunctionTest)
    result = execute( `SELECT {[Measures].[Unit Sales]} ON 0, VisualTotals({[Customers].[All Customers], `
                   && `[Customers].[USA], [Customers].[USA].[CA], [Customers].[USA].[OR]}) ON 1 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = values( result )
                                        exp = VALUE string_table( ( `142407` ) ( `142407` ) ( `74748` ) ( `67659` ) ) ).
    " CurrentDateMember: a fixed date, exact; after a date before the data, the first member after it
    result = execute( `SELECT {CurrentDateMember([Time].[Time], "[Ti\me]\.[1997]\.[Q2]\.[5]")} ON 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result ) exp = VALUE string_table( ( `[Time].[1997].[Q2].[5]` ) ) ).
    result = execute( `SELECT {CurrentDateMember([Time].[Time], "[Ti\me]\.[1996]\.[Q4]", AFTER)} ON 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result ) exp = VALUE string_table( ( `[Time].[1997].[Q1]` ) ) ).
  ENDMETHOD.

  METHOD crossjoin_result_limit.
    DATA(limit) = zzxxmla1_cl_mdx_engine=>result_limit.
    DATA(description) = ``.
    zzxxmla1_cl_mdx_engine=>result_limit = 10.
    " 5 product families (with the unassigned one) x 3 store countries: 15 tuples, built only below the limit
    TRY.
        execute( `select CrossJoin([Product].[Product Family].Members, [Store].[Store Country].Members) on 0 `
              && `from [ZFMSALES]` ).
      CATCH zzxxmla1_cx_xmla INTO DATA(error).
        description = error->description.
    ENDTRY.
    zzxxmla1_cl_mdx_engine=>result_limit = limit.
    cl_abap_unit_assert=>assert_char_cp( act = description exp = `*Size of CrossJoin result (*) exceeded limit (10)` ).
    " the limit restored: the same crossjoin is built
    execute( `select CrossJoin([Product].[Product Family].Members, [Store].[Store Country].Members) on 0 `
          && `from [ZFMSALES]` ).
  ENDMETHOD.

  METHOD native_crossjoin.
    " the stores in hierarchy order, not in the order of the set (NonEmptyTest); answer of the reference server
    DATA(result) = execute( `select NonEmptyCrossJoin({[Store].[USA].[OR].[Portland], [Store].[USA].[OR].[Salem], `
                         && `[Store].[USA].[CA].[San Francisco], [Store].[USA].[WA].[Tacoma]}, {[Product].[Food]}) `
                         && `on 0 from [ZFMSALES]` ).
    cl_abap_unit_assert=>assert_equals( act = tuples( result )
                                        exp = VALUE string_table( ( `[Store].[USA].[CA].[San Francisco],[Product].[Food]` )
                                                                  ( `[Store].[USA].[OR].[Portland],[Product].[Food]` )
                                                                  ( `[Store].[USA].[OR].[Salem],[Product].[Food]` )
                                                                  ( `[Store].[USA].[WA].[Tacoma],[Product].[Food]` ) )
                                        msg = concat_lines_of( table = tuples( result ) sep = ` | ` ) ).
  ENDMETHOD.

  METHOD native_crossjoin_large_level.
    " Excel's drilled pivot field: the All member and a level of more than MaxConstraints (1000) members. The
    " multi-variant expansion reads it natively; interpreted, 10,282 customers x 52 promotions exceed the limit
    DATA(limit) = zzxxmla1_cl_mdx_engine=>result_limit.
    zzxxmla1_cl_mdx_engine=>result_limit = 20000.
    TRY.
        DATA(result) = execute( `select NON EMPTY CrossJoin({[Customers].[All Customers], [Customers].[Name].Members}, `
                             && `{[Promotions].[All Promotions], [Promotions].[Promotion Name].Members}) on 0 `
                             && `from [ZFMSALES]` ).
      CLEANUP.
        zzxxmla1_cl_mdx_engine=>result_limit = limit.
    ENDTRY.
    zzxxmla1_cl_mdx_engine=>result_limit = limit.
    DATA(names) = tuples( result ).
    cl_abap_unit_assert=>assert_equals( act = names[ 1 ] exp = `[Customers].[All Customers],[Promotions].[All Promotions]` ).
    cl_abap_unit_assert=>assert_true( xsdbool( lines( names ) > 5581 ) ).
  ENDMETHOD.

ENDCLASS.
